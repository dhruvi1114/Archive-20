# Testing Strategy

## 1. Who tests

The **existing Self-Test Agent** (`sarvadhi-sentinel/`) is the only testing agent. No second testing agent is created (CLAUDE.md, master instructions §23). Coding agents write unit/integration tests inside their own workstream; Sentinel is the shared regression + smoke gate that runs at the end of every module cycle.

## 2. Sentinel today vs what it must become (M0 task)

Today `sarvadhi-sentinel/` is the Elvee copy: `package.json` name `elvee-sentinel`, `config.js` points at Elvee PLP routes (`/necklace`, `/pendant`) and Elvee guest endpoints (`header`, `promotional-strips`, `currency`), `.env.example` uses Elvee ports (6030/7001/9000). Running it against this platform would report green nonsense (R-11).

M0 rewires it — keeping the harness, replacing the targets:

| File | Change |
|---|---|
| `package.json` | name → `association-sentinel` |
| `config.js` | `apiEndpoints` → this platform's guest endpoints (`health`, `public/settings`, `public/events`); `customerRoutes` → `/`, `/login`, `/dashboard`; `adminRoute`/`adminReadySelector` → this admin; per-suite `only` keys per module |
| `.env.example` | ports 4000 (backend) / 3000 (customer) / 3001 (admin); `TERIFF`/`PLAN` unchanged (same AES scheme, ADR-004) |
| `run.js` | suites extended per module (see §4); `lib.js` crypto helpers reused as-is |

`lib.js` (`makeCrypto`, `portOpen`, `writeReport`) needs **no change** — the encryption scheme is identical by design, which is exactly why ADR-004 chose Elvee parity.

## 3. Test levels

| Level | Tool | Owner | Scope |
|---|---|---|---|
| Unit | Vitest | coding agent | Services: fee resolution, status transitions, money math, permission checks, template rendering. Pure functions, mocked repositories. |
| Integration (API) | Vitest + Supertest against a test Postgres | coding agent | Route → middleware → service → real DB. Migrations applied, seeds loaded, DB truncated between tests. |
| Contract | Sentinel `api` suite | Sentinel | Encrypted round-trip, envelope shape, status codes, auth/permission negatives. |
| E2E / smoke | Sentinel `customer` + `admin` suites (Playwright) | Sentinel | The module's primary journey clicked end to end. |
| Manual UX pass | coding agent, then user | both | Four-line rubric (`ux-principles.md` §2 — the interface answers it; a screen that narrates the answers fails) + state coverage per screen. |

Minimum bar per module: every service method with a branch has a unit test; every endpoint has at least one 2xx and one negative (401/403/422/409) integration test; the module's headline journey has one Sentinel E2E case.

## 4. Sentinel suites by module

| Suite key | Added in | Asserts |
|---|---|---|
| `health` | M0 | backend/customer/admin ports open, `GET /health` = 200, `db: "up"` |
| `crypto` | M0 | encrypt→POST→decrypt round-trip; malformed ciphertext → 400 `INVALID_REQUEST`; `decrypted_data` absent when `APP_ENV != local` |
| `schema` | M0, re-run every cycle | `db:check-comments` returns zero rows (ADR-013); `prisma migrate status` no drift; every index listed for shipped modules exists. **`AuditLogs` UPDATE/DELETE rejection is asserted only where a non-superuser `assoc_app` role exists (`deployment.md` §8b) — skipped in local, because a superuser would pass it vacuously** |
| `auth` | M1 | signup→OTP→login→refresh→logout; wrong password 401; lockout after 5; member token on an admin route → 403 |
| `masters` | M2 | duplicate code → 409; ACCOUNTS may price and ADMIN may not (rbac.md §3); overlapping active price → **409 not 500**; resolver returns the published amount with tax computed; money is a string not a JSON number; no configured fee → 409 never ₹0; in-use category delete → 409; `limit` clamped to 100; public catalogue leaks no internal fields. Creates and removes its own throwaway category |
| `rbac` | M1 | for each seeded role, one allowed call = 2xx and one forbidden call = 403 |
| `profile` | M3 | profile read/update, critical field → change request, document upload/limit/mime rejection, unauthorised download → 404 |
| `application` | M4 | draft→submit→admin approve through all stages→member created + invoice issued; return→resubmit; double-approve → 409 |
| `member-admin` | M3 | member list filters + pagination cap (limit>100 clamped), single-statement list query, suspend/reactivate, document upload/download authorization (`file-storage.md` §8) |
| `billing` | M4 (issue) + M5 (pay) | invoice issue, MockProvider payment success → invoice PAID + receipt + member ACTIVE; webhook replay → single effect; refund > balance → 409 |
| `renewal` | M6 | term expiry sweep, renewal invoice, reminder rows created once (unique constraint holds) |
| `event` | M7 | publish, register (free + paid), capacity limit, duplicate registration → 409, check-in |
| `communication` | M8 | notice publish fan-out count matches audience, outbox drains, failed row retryable |
| `directory` | M9 | only ACTIVE + visible members listed, hidden fields absent for anonymous, search returns expected row |
| `reports` | M10 | dashboard counts match seeded fixtures; export returns a file with the expected header row |

`node run.js --only=<suite>` during development; full run before the module is proposed for approval.

### The harness must not fail on its own traffic (M2)

M2's first full run reported three suites red — rbac, masters and admin — all with `429 RATE_LIMITED`. Nothing was broken: the `auth` suite deliberately spends five failed sign-ins proving the lockout works, and every later suite then signed in again, exhausting the per-IP login throttle (api-conventions.md §9).

Fixed by caching one admin token per account for the whole run, which is also what a real client does. The lesson generalises: **a gate that trips its own guard rails produces false reds, and a team that sees false reds stops reading the gate.**

Related, and worth remembering: the throttle is an in-memory store (OQ-14), so restarting the API clears it. Convenient locally; it also means the limit does not survive a deploy or span instances.

### Restart the stack before a gating run — learned the hard way (M1)

M1's first full run reported a customer failure: an anonymous visitor was not redirected off `/dashboard`. The guard was correct; the **dev server had been running since before the code was written** and was serving a stale `.next` build. Nearly an hour went into chasing a bug that did not exist.

Before any run whose result is used to gate a cycle:

```bash
pkill -f "next dev"; rm -rf customer/.next     # customer
# restart backend and admin too, so no process predates the code under test
```

A false FAIL costs an investigation. A false PASS from the same cause costs a release. Neither is acceptable from the gate that decides whether a cycle ships.

### An API suite that never calls an endpoint is not coverage (M4)

M4's `application` suite went green while application document **verify, remove
and download all returned 500**. The suite uploaded documents and approved
stages, so the flow looked covered — but it never called verify, and no download
route existed at all. Stage 1 of the workflow *is* document verification, so the
one thing that stage exists for was broken in a passing cycle.

Two rules follow:

- **Every route in a module's surface gets at least one assertion, including the
  ones the happy path skips.** A route with no test is an untested route however
  green the suite is.
- **Drive the UI in a browser before a cycle is offered for approval.** The 500s
  above sat behind buttons nobody had clicked; so did an SSR hydration mismatch
  and a first-load 409. The API suite cannot see any of them. Screenshots are
  part of the evidence, because design regressions are only visible by looking.

### Route params: name every one in the schema

`validateRequest` **replaces** `req.params` with zod's parsed output, and zod
strips keys the schema does not mention. A `/:id/documents/:documentId` route
validated with a schema that only names `id` therefore hands the handler
`documentId === undefined`, and `BigInt(undefined)` throws — a 500 from a route
that looks correctly validated. Any schema used on a route must name every
parameter that route carries.

## 5. Performance checks in self-test

Every list endpoint touched by a module is asserted to: return within 800 ms on the seeded dataset (≥5k members, ≥20k invoices, ≥2k applications), issue a bounded number of SQL statements (no N+1 — asserted by a query counter in integration tests), and honour `limit ≤ 100`.

## 6. Security checks in self-test

Per module: unauthenticated call → 401; wrong-audience token → 403; lower-privilege role → 403; another member's resource → 404; SQL-injection string in `search` returns a normal empty result (parameterisation proof); uploaded `.exe`/oversize file rejected; error responses contain no stack trace, table name or SQL fragment.

## 7. Test data

`prisma/seed.ts --env=test` produces deterministic fixtures: 4 roles, 1 super admin, 3 admins (one per role), 5 categories/tiers, fee structures, 25 members across every status, 10 applications across every status, 40 invoices across every status, 6 events, 10 notices. Sentinel accounts come from `.env` (never committed, never real user data).

## 8. Bug loop

Sentinel writes a timestamped markdown report to `sarvadhi-sentinel/reports/`. Failures are recorded with severity (**Blocker** — journey impossible or data corrupted · **Major** — feature wrong, workaround exists · **Minor** — cosmetic/copy) plus repro steps, expected vs actual, and the owning agent. Blockers and Majors go back to the owning coding agent; the module cannot be marked `SELF_TEST_PASSED` while any Blocker or Major is open. After fixes, the **full** suite re-runs (not just the failing case) to catch regressions.

## 9. Definition of done for testing (per module)

- Unit + integration tests green in CI-equivalent local run.
- `node run.js` (full) exits 0 and the report is attached to the module plan file.
- Negative security cases from §6 pass.
- Performance assertions from §5 pass.
- `npm run db:check-comments` exits 0 — no table or column without a database comment (ADR-013).
- No open Blocker/Major from any earlier module's suite (regression clean).
