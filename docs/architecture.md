# Architecture

## 1. System shape

```
Public visitor ─┐
Applicant ──────┼──▶ customer/  (Next.js + TS)  ─┐
Member ─────────┘                                │
                                                 ├──▶ backend/ (Node + Express + TS)
Super Admin ────┐                                │      Route → Middleware → Validation
Admin ──────────┼──▶ admin/     (React + Vite)  ─┘      → Controller → Service → Repository
Approver ───────┤                                       → Prisma → PostgreSQL
Accounts ───────┘

sarvadhi-sentinel/  ──▶ hits backend + both frontends, writes reports/
```

Backend owns business rules, authorization, validation, transactions and persistence. Frontends own presentation only. No business rule is duplicated across the two frontends.

## 2. Repository layout

```
BI-Platform/
├── backend/            # exists (skeleton) — extend, do not rewrite
│   ├── prisma/
│   │   ├── schema/           # split schema files (Prisma multi-file)
│   │   ├── migrations/
│   │   └── seed.ts
│   └── src/
│       ├── app.ts, index.ts
│       ├── config/           # env flavours: .env, .env.local, .env.dev, .env.staging, .env.production
│       ├── constant/         # ERROR_TYPES, RES_TYPES, RES_STATUS, END_POINTS
│       ├── locales/          # NEW — i18n (en.json), i18n instance
│       ├── helpers/          # NEW — encryption.ts, documentNumber.ts, storage.ts
│       ├── middleware/       # auth, adminAuth, permission, decryption, validation, error, security, pagination, audit
│       ├── modules/<domain>/ # types | repository | service | controller | routes
│       ├── jobs/             # NEW — scheduler (renewal reminders, notification queue drain)
│       ├── logger/  utils/  types/  db/  routes/
├── customer/           # empty — Next.js 14 App Router + TS (M0)
├── admin/              # empty — React 18 + Vite + TS (M0)
├── sarvadhi-sentinel/  # exists — rewire from Elvee to this stack (M0)
└── docs/               # this plan
```

## 3. Backend layering (non-negotiable)

| Layer | May do | May NOT do |
|---|---|---|
| Route | Mount path, attach `authenticate` / `authorize(...)` / `validateRequest` | Contain logic |
| Middleware | Decrypt payload, authn, authz, validate, paginate, audit, error map | Query the DB for business data |
| Controller | Read validated input, call one service, hand result to `handleApiResponse` | Business rules, Prisma calls |
| Service | Business rules, transitions, transactions, `AppError`, notifications | Raw `req`/`res` access |
| Repository | Prisma client writes, raw SQL reads, pagination | Business rules, throwing domain errors |

Cross-module calls go **service → service**, never controller → controller and never repository → repository of another module.

## 4. Request lifecycle

```
HTTP request
  → helmet / cors / rate-limit
  → express.json
  → decryptPayload        (req.body.data ciphertext → object; passthrough when plaintext & allowed)
  → i18n init             (locale from `lan` header, default en)
  → responseHandler       (request log + latency)
  → authenticate          (member JWT) | authenticateAdmin (admin JWT)
  → authorize('module.action')  (admin only; DB-backed permission set on token claims + revalidated)
  → validateRequest       (zod: body | query | params)
  → controller → service → repository → Prisma → PostgreSQL
  → handleApiResponse     (envelope + AES/gzip encrypt of `data`)
  → ErrorHandler          (AppError → status + i18n message; never leaks stack)
```

## 5. Encryption boundary (Elvee-parity, ADR-004)

- Algorithm: `AES-256-CBC` via `crypto-js`, payload gzipped with `pako`, 16 random chars prefixed before compression, Base64 out.
- Env keys: `CHIPER` (algorithm label), `TERIFF` (32-char key), `PLAN` (16-char IV) — identical names to Elvee so the frontends' `enc-dec` util and Sentinel port over unchanged.
- Request: clients POST `{ "data": "<ciphertext>" }`; `decryptPayload` replaces it with the parsed object before validation.
- Response: `handleApiResponse` encrypts the `data` field only; `success`, `statusCode`, `message`, `pagination` stay plaintext so infra/monitoring can read them.
- `APP_ENV=local` additionally returns `decrypted_data`. Never in dev/staging/production.
- File uploads (`multipart/form-data`) and webhook callbacks bypass decryption — documented exception list in `api-conventions.md`.

## 6. i18n

`i18n` package, `src/locales/en.json`, header field `lan`, default from `APP_LANGUAGES` env (`en`). Every user-facing string — success messages, `AppError` messages, validation messages, email/WhatsApp/in-app notification templates — resolves through `i18n.__('<namespace>').<key>`. Namespaces mirror modules: `common`, `auth`, `member`, `application`, `approval`, `billing`, `payment`, `renewal`, `event`, `communication`, `directory`, `rbac`, `document`, `encryption`.

## 7. Frontends

**customer/** — Next.js 14 App Router + TypeScript. Public pages SSR/ISR for SEO (home, about, events, directory). Authenticated member area client-rendered. Redux Toolkit + redux-persist (auth, locale). Axios `BaseService` with interceptors: attach JWT, encrypt request body, decrypt response `data`, sign out on 401. Tailwind + Ant Design 5 (same stack as Elvee frontends).

**admin/** — React 18 + Vite + TypeScript (CLAUDE.md says React, not Next; admin needs no SEO). Same Redux/axios/encryption/AntD/Tailwind conventions so components and utils are portable between the two apps. Route guards read the permission set from the token but **the backend re-checks every call**.

Shared-by-copy (not a package, to keep the two apps independently deployable): `utils/enc-dec.ts`, `services/BaseService.ts`, `constant/endpoints.ts`, design tokens.

## 8. Environments & config

`APP_ENV` ∈ `local | dev | staging | production`; base `.env` overlaid by `.env.<APP_ENV>`. Secrets (DB URL, JWT secret, AES keys, SMTP, gateway keys) never committed; `.env.example` per app lists every key with a dummy value.

## 9. Jobs / scheduling

`node-cron` inside the backend process for MVP: renewal reminder sweep (daily), notification queue drain (every minute), token/OTP pruning (daily), invoice overdue marking (daily). Each job is idempotent and logs a run record. Extraction to a separate worker is a post-MVP option (ADR-009).

## 10. Observability

Winston logger (existing), request log with status/method/url/latency/actor, `AuditLogs` table for business events, health endpoint `GET /api/v1/health` returning app + DB status. No PII, no tokens, no KYC data, no decrypted payloads in logs.
