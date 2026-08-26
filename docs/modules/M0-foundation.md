# M0 — Foundation & Shared Core

**Status:** Agent B scope COMPLETE (backend + admin shell, 2026-08-12) — awaiting Sentinel run and user approval. Agent A scope (customer + Sentinel) tracked separately.
**Migration owner:** Agent B — migration `20260812063253_m0_replace_baseline_identity` applied; `db:check-comments` 11 tables / 106 columns, exit 0.
**Blocking OQ:** none. Git is deferred by user decision (see below); OQ-10 (hosting/storage) is absorbed by the storage adapter (ADR-017); SMTP credentials arrive later and are absorbed by a console/Mailhog transport (A-13).
**Depends on:** —

## Version control — deferred by user decision (R-13, accepted risk)
Git comes later. Interim controls, mandatory while it is absent:
1. **File ownership is absolute** — the cycle's ownership table decides who may touch which file. No exceptions, because there is no merge tool to save us.
2. **Tar snapshot at every cycle boundary**: `tar -czf ~/assoc-snapshots/BI-Platform-$(date +%F-%H%M)-m0-start.tar.gz --exclude node_modules --exclude .next --exclude dist .` — taken at cycle start and at cycle end, stored outside the project directory.
3. `.gitignore` is still written now (`node_modules`, `.env*` except `.env.example`, `dist`, `.next`, `uploads`, `reports`, `*.dump`) so `git init` later is a one-liner with nothing leaked.
4. **Re-raise before the first deploy.** A `prisma/migrations` history with no version control is the sharpest edge in this project.

## Goal
Every cross-cutting mechanism exists, is tested and is frozen: encryption, i18n, errors, config, identity schema, audit, storage, notification outbox, jobs, observability — plus both frontend shells and a Sentinel that actually points at this platform. No business feature.

## Agent B — backend + admin shell
1. Env flavours (`.env`, `.env.local/.dev/.staging/.production`), zod-validated config loader, `APP_ENV` wiring, **`PORT` default corrected to 4000** (skeleton says 3000, which collides with the customer app — `versions.md`).
2. `helpers/encryption.ts` — AES-256-CBC (crypto-js) + gzip (pako) + 16-char noise prefix, keys `CHIPER`/`TERIFF`/`PLAN` (Elvee-identical, ADR-004).
3. `middleware/decryption.ts` (`req.body.data` → object), bypass list (multipart, webhooks, health); `handleApiResponse` encrypts `data`, adds `decrypted_data` only when `APP_ENV=local`. **`express.json({verify})` captures `req.rawBody`** for future webhook signatures (ADR-018).
4. `locales/` — i18n instance (`lan` header, `APP_LANGUAGES`), `en.json` with all namespaces; every `AppError`/success message keyed.
5. Prisma multi-file schema; migration: extensions (`citext`, `pg_trgm`, `btree_gist`), `Users`, `AdminUsers`, `Roles`, `Permissions`, `RolePermissions`, `AdminUserRoles`, `AuditLogs`, `SystemSettings`, `JobRuns`, **`NotificationTemplates`, `Notifications`** (ADR-015); replaces the skeleton baseline `User`. Every model/field gets a `///` doc-comment and a matching `COMMENT ON` block in the same `migration.sql` (ADR-013).
6. `scripts/check-db-comments.ts` + `npm run db:check-comments` — coverage query from `database-design.md` §I, exits 1 on any gap; wired into husky pre-push and the Sentinel `schema` suite.
7. `helpers/audit.ts` (transaction-aware), `helpers/storage.ts` (`StorageAdapter` + local driver per `file-storage.md`, path containment assertion), `helpers/documentNumber.ts` (transactional sequence).
8. **Notification outbox core** (ADR-015): outbox writer, drain job (`FOR UPDATE SKIP LOCKED`, batch 50, exponential backoff, max 5 attempts), `EmailChannel` (nodemailer — **console transport in `local`, Mailhog/Ethereal in `dev` until real SMTP arrives**, A-13), `InAppChannel`, template renderer. Notices/WhatsApp/admin UI stay in M8.
9. `node-cron` scaffold behind `ENABLE_JOBS` with `JobRuns` recording; jobs: notification drain, token/OTP prune, `JobRuns` prune.
10. **Observability** (`observability.md`): winston JSON formatter with the redaction denylist, `requestId` propagation + echo in error responses, slow-request warn, `GET /api/v1/health` and `/health/ready`, crash handlers emailing `CRASH_MAIL`.
11. `RULES.md` amended for ADR-005 (hybrid reads).
12. `admin/` scaffold: Vite 6 + React 18 + TS, React Router v6, Redux Toolkit + persist, axios `BaseService` (auth header, encrypt request, decrypt response, 401 → sign-out), AntD 5 `ConfigProvider` + Tailwind 3.4 driven by the **monochrome token set** (`design-system.md` — ElevenLabs-style black & white, AntD's default blue fully overridden), `components/ui` primitives, permission-aware shell, 403/404/500.

## Agent A — customer shell + Sentinel
1. `customer/` scaffold: Next.js 14 App Router + TS, Redux + persist, same `BaseService` interceptors, AntD + Tailwind + tokens, public layout + member shell, 404/500/offline.
2. `utils/enc-dec.ts` for both apps; round-trip verified against the backend.
2b. Token layer: neutral scale + semantic roles + dark-mode tokens in `tailwind.config.ts` and `theme.ts`; a lint rule (or review gate) rejecting raw hex outside the token file.
3. Shared UI primitives per `design-system.md`: Button, Input, Select, FileUpload, Table, Card, StatusChip (central status→variant map), Alert, Dialog, Drawer, Tabs, Stepper, Timeline, EmptyState, Skeleton, ErrorState, Toast, MoneyText, PermissionGate.
4. Sentinel rewire (R-11): `package.json` → `association-sentinel`; `config.js` targets this platform; `.env.example` ports 4000/3000/3001; `health` + `crypto` + `schema` suites; README updated.
5. Backup script + cron from `backup-recovery.md` §3 installed on the dev host, and **one rehearsed restore** (§4) recorded in this file.

## Contracts frozen this cycle
Response envelope · error code table · encryption format · i18n namespace list · identity schema · audit row shape · notification outbox row + template contract · `StorageAdapter` interface · design tokens · `BaseService` contract · ports.

## Self-test (Sentinel)
`health`, `crypto`, `schema`. All three ports open · `/health` 200 with `db: "up"` · `/health/ready` reports migration state · encrypted POST round-trip · malformed ciphertext → 400 `INVALID_REQUEST` · `decrypted_data` absent when `APP_ENV != local` · `db:check-comments` zero rows · a test log line containing a password/token is redacted.

## Definition of done
- `npm run dev` green in backend, customer, admin; ports 4000/3000/3001.
- `prisma migrate dev` clean from an empty DB; `migrate status` no drift; seeds idempotent.
- `npm run db:check-comments` exits 0, spot-checked with `\d+` in psql.
- Encrypted round-trip proven from customer, admin and Sentinel.
- Outbox proven: a queued row is drained and marked SENT by the job; a forced SMTP failure retries then FAILS visibly, and rolls back nothing.
- Backup script runs and one restore has been rehearsed.
- Lint, format, husky, TS strict green. No business logic in this cycle.

## Approval checklist for the user
Envelope + error shape · monochrome token set rendered in both apps (light + dark) · outbox proven with the interim mail transport · snapshot procedure in place (git deferred) · Sentinel report attached.

---

## Cycle record — 2026-08-12

**Sentinel report:** `sarvadhi-sentinel/reports/smoke_2026-08-12-08-41-47_pass.md` — RESULT: PASS (health · api · crypto · schema · customer; admin suite skipped, see gaps).

### Verified by the Planning Agent independently (not taken on the coding agents' word)
| Check | Result |
|---|---|
| Cross-implementation crypto (Sentinel `lib.js` → backend → back) with a multibyte payload | 200, byte-identical round-trip, `rawBody` captured |
| Malformed ciphertext | 400 `INVALID_REQUEST` |
| zod failure path | 422 `VALIDATION_ERROR` with a per-field map |
| `GET /health` · `/health/ready` | 200, `db:"up"`, `pendingMigrations:0`, `storage:"up"` |
| `prisma migrate status` | no drift, 2 migrations |
| `npm run db:check-comments` | **exit 0 — 11 tables / 106 columns, all commented** |
| `_selftest/echo` gating | mounted only under `if (environment.isLocal)` |
| Backup + **restore rehearsal** | PASS — 84 KB dump restored into a scratch DB: 12 tables, 39 permissions, 4 roles, 2 migrations, 0 uncommented columns; scratch DB dropped |

### Bugs found and fixed inside the cycle
1. **latin1 vs UTF-8 in `backend/src/helpers/encryption.ts`** — gzip emits bytes > 0x7F, so backend base64 diverged from customer/admin/Sentinel. Each side round-tripped with itself, so unit tests passed and only the integration boundary broke. Found by Agent A, verified by the Planning Agent, fixed by Agent B. **This is the case for the Sentinel gate in a single bug.**
2. Same class of bug in `admin/src/utils/enc-dec.ts` — bare `window.btoa` is latin1. Found and fixed by Agent B in its own work.
3. `dotenv({override:true})` let a blank line in `.env.<flavour>` silently shadow an injected `DATABASE_URL` → replaced by an explicit precedence loader (ADR-023).

### Deviations from the plan, all recorded as ADRs
ADR-020 `prisma.config.ts` migrations path · ADR-021 hand-written partial unique indexes (drift-probed) · ADR-022 local-only `_selftest/echo` · ADR-023 env precedence · ADR-024 comments generated from the schema.

### Cleanup applied after the agents finished
`echarts`, `echarts-for-react`, `react-quill` were installed in `admin/` with zero imports — removed (master instructions §22; `react-quill` also pre-commits to rich text that `security.md` §2 gates behind server-side sanitisation). Admin rebuilt clean afterwards. Sentinel `crypto` probe retargeted from a 404 on `auth/login` to the echo endpoint, so it proves a real round-trip instead of proving the middleware did not reject.

### Gaps carried out of M0 (none block M1)
| # | Gap | Disposition |
|---|---|---|
| 1 | Sentinel **admin suite skipped** — no admin login exists yet | Closes in M1 when admin auth lands |
| 2 | `REVOKE UPDATE, DELETE ON "AuditLogs"` documented but not executed — local connects as superuser, where the revoke is a silent no-op | Provisioning step, `deployment.md` §8b; Sentinel asserts it where a non-superuser role exists |
| 3 | **Off-host backup copy unconfigured** (`RCLONE_REMOTE` unset) — the copy is local-only, which is not a backup | Needs the client's backup destination (OQ-11) |
| 4 | 5 high `npm audit` advisories in the Next dependency family, fixable only by Next 15/16 (forbidden by ADR-014) | User decision before go-live, `versions.md` |
| 5 | Light/dark visual review of the monochrome tokens by a human | Your approval step below |
| 6 | Backend `.env.local` holds a real DB password and is on disk unencrypted with git deferred | Acceptable locally; rotate before any shared environment |

