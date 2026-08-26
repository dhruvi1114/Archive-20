# Framework & Runtime Version Decisions

Locked in planning so the two coding agents cannot pick different majors. Verified against this machine on 2026-08-12: Node `v24.13.1`, npm `11.10.1`, psql `18.2`, Docker installed (daemon currently stopped).

## Runtime & database

| Component | Pinned | Why |
|---|---|---|
| Node.js | **24.x LTS** (`.nvmrc` = `24`, `engines.node = ">=24 <25"`) | Already the machine's version and an Active LTS line. One version across backend + both frontends + Sentinel. |
| npm | **11.x**, `package-lock.json` committed, `npm ci` in deploys | Lockfile reproducibility |
| PostgreSQL | **18.x** (dev = local 18.2; staging/production must match major) | Local already 18; a major mismatch between dev and prod is a silent-failure source |
| Extensions | `citext`, `pg_trgm`, `btree_gist` | Case-insensitive email, directory search, fee daterange exclusion |
| TypeScript | **5.7.x**, `strict: true` everywhere | Matches skeleton |

## Backend

| Package | Pinned | Note |
|---|---|---|
| Express | **4.21.x** | Skeleton and Elvee are both Express 4. Express 5 is stable but changes error/async and router semantics — no MVP benefit, real regression risk. Revisit post-MVP (ADR-014). |
| Prisma + @prisma/client | **6.x** | Skeleton version. Multi-file schema enabled. |
| zod | **3.24.x** | Skeleton uses 3.x; do not jump to 4 mid-project |
| crypto-js | **4.2.x** | Must match the frontends and Sentinel exactly (ADR-004) |
| pako | **2.1.x** | Same |
| i18n | **0.15.x** | Elvee parity |
| jsonwebtoken | **9.x** | |
| bcryptjs | **2.4.x** | Skeleton already uses bcryptjs (pure JS, no native build). Do **not** mix with `bcrypt`. |
| helmet / cors / express-rate-limit | **8.x / 2.8.x / 7.x** | Skeleton versions |
| winston | **3.x** | Skeleton logger |
| nodemailer | **6.9.x** | Email channel |
| node-cron | **3.x** | Jobs (ADR-009) |
| multer | **1.4.x** | Uploads. Skeleton has none yet; chosen over `express-fileupload` (Elvee's) because it streams to disk and enforces limits before buffering. |
| exceljs / pdfkit | **4.x / 0.15.x** | Report export, invoice + receipt PDFs |
| Vitest + Supertest | **2.x / 7.x** | Unit + integration tests |

## Customer app

| Package | Pinned | Note |
|---|---|---|
| Next.js | **14.2.35** (App Router) | Elvee parity; AntD 5 + React 18 combination is proven there. Next 15/React 19 needs an AntD compat shim — no MVP benefit (ADR-014). |
| React / React DOM | **18.3.x** | |
| Redux Toolkit + react-redux + redux-persist | **2.x / 9.x / 6.x** | |
| axios | **1.19.x** | Interceptors do encrypt/decrypt/401. Bumped from 1.7.x on 2026-08-12 under the security-advisory clause below (~30 advisories); same version in backend, customer and admin |
| antd | **5.x** | `ConfigProvider` themed from design tokens |
| tailwindcss | **3.4.x** | v4 changes the config model and breaks the AntD integration recipe — stay on 3.4 for MVP |
| crypto-js / pako | **4.2.x / 2.1.x** | Byte-identical scheme to the backend |

## Admin app

| Package | Pinned | Note |
|---|---|---|
| Vite | **6.x** | |
| React / React DOM | **18.3.x** | Same major as customer so `ui/` components port |
| react-router-dom | **6.x** | ADR-012 (React, not Next) |
| Redux Toolkit / axios / antd / tailwind / crypto-js / pako | same as customer | One set of habits, one set of bugs |

## Application libraries added in M0 (all three apps kept in lockstep)

| Package | Version | Where | Why |
|---|---|---|---|
| `@ant-design/icons` | 5.x | customer, admin | The single icon set (`design-system.md` §1). Never mixed with another. |
| `@ant-design/cssinjs` | 1.x | customer, admin | `StyleProvider hashPriority="high"` + Tailwind `preflight:false` — the documented way to stop AntD and Tailwind fighting |
| `@ant-design/nextjs-registry` | 1.x | customer | SSR style extraction for the App Router |
| `react-hook-form` + `yup` + `@hookform/resolvers` | 7.x / 1.x / 3.x | customer, admin | Form state + schema validation. **Client-side only** — the backend re-validates everything with zod; the frontend schema is UX, never the security boundary |
| `sonner` | 1.x | customer, admin | Toasts |
| `dayjs` | 1.11.x | customer | AntD's date primitive; avoids pulling in moment |
| `clsx` + `tailwind-merge` | 2.x | customer | Class composition for the `ui/` primitives |
| `nodemailer` | 6.9.x | backend | `EmailChannel` |
| `node-cron` | 3.x | backend | Jobs (ADR-009) |
| `i18n` | 0.15.x | backend | Elvee-parity message layer |
| `tsc-alias` | 1.8.x (dev) | backend | Rewrites path aliases after `tsc`; `npm start` from `dist/` is broken without it |

**Deliberately NOT installed yet** — `echarts` / `echarts-for-react` (M10 dashboards) and `react-quill` (M8 rich-text notices) were installed during M0 with zero imports and have been removed. Master instructions §22 forbids unnecessary dependencies, and `react-quill` additionally pre-commits to rich text that `security.md` §2 says requires server-side sanitisation before it may ship. They return in their own cycle, with that sanitisation decision made first.

## Sentinel

Playwright **1.5x**, axios **1.19.x**, crypto-js **4.2.x**, pako **2.1.x** — already installed; only config/targets change in M0.

## Ports (single source of truth)

| App | Local port |
|---|---|
| Backend API | **4000** |
| Customer | **3000** |
| Admin | **3001** |
| PostgreSQL | 5432 |

> Conflict found in review: `backend/.env.example` currently says `PORT=3000`, which collides with the customer app. M0 changes it to 4000 and updates `config.ts` default.

## Upgrade policy

No major-version bump of anything in this table during the MVP. A minor/patch bump is fine when it fixes a security advisory (`npm audit`). Any major bump after MVP needs an ADR line and a full Sentinel run.

### Applied under this clause (2026-08-12, M0)
`axios 1.7.x → 1.19.0` · `next → 14.2.35` · `postcss → 8.5.26` · `tsx → 4.23.12`. Applied across backend, customer and admin so the three stay identical.

### OPEN — needs a decision
`npm audit` reports **5 high advisories in the Next.js dependency family** that are only fixable by moving to Next 15/16, which ADR-014 forbids for the MVP (AntD 5 + React 18 parity). Options: (a) accept and revisit post-MVP, (b) raise an ADR to move the customer app to Next 15 + React 19 with the AntD compat shim, (c) re-check whether a 14.x patch closes them before go-live. Nothing is exploitable through this app's own routes today; the risk is transitive/dev-time. **User decision required before go-live, not before M1.**
