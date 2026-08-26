# Implementation Plan

## 1. Delivery model

Work ships in **module cycles**. One cycle at a time. A cycle is done only when the user approves it.

```
PENDING → PLAN CONFIRMED → IN_PROGRESS (Agent A ∥ Agent B) → SELF_TEST (Sentinel)
        → FIXES (owning agent) → SELF_TEST re-run → AWAITING_APPROVAL → APPROVED → next cycle
```

Rules:
1. Only one module is `IN_PROGRESS` at a time. No starting the next cycle because the current one is "nearly done".
2. Contracts (Prisma models + API signatures for that module) are frozen and written down **before** either agent writes code.
3. One migration owner per cycle. The other agent does not touch `prisma/`.
4. A module cannot be marked done with an open Blocker or Major from Sentinel.
5. Blocking open questions for a module must be answered before that cycle starts (listed per module file).
6. No cycle closes while `npm run db:check-comments` fails — every table and column shipped that cycle carries a database comment (ADR-013).
7. **Each cycle is a contractual milestone.** The proposal gives the client 5 working days to sign off a milestone and states that input delays shift the schedule (NFR-6). The module plan file's approval checklist *is* that sign-off, and the date it was requested/received is recorded in `implementation-status.md`.

## 2. Cycle sequence (corrected — ADR-019)

| Cycle | Module | Blocking OQs | Migration owner |
|---|---|---|---|
| M0 | Foundation & shared core (incl. notification outbox, observability, storage adapter) | **OQ-12 git** | Agent B |
| M1 | Authentication, RBAC, app shells | OQ-1 (permission matrix) | Agent B |
| M2 | Masters: categories, tiers, fees, document types | OQ-2, OQ-9 | Agent B |
| M3 | Member record, profile, KYC, member management | — | Agent A |
| M4 | Application, approval workflow, activation, invoice issuance | OQ-3, OQ-8 | Agent B |
| M5 | Payments, receipts, refunds, reconciliation, dunning | OQ-4 (non-blocking — adapter) | Agent B |
| M6 | Membership renewal | OQ-6 | Agent B |
| M7 | Events | — | Agent B |
| M8 | Communication & notifications (notices, WhatsApp, outbox UI) | OQ-5 (non-blocking — adapter) | Agent B |
| M9 | Directory & public website | OQ-7 | Agent A |
| M10 | Dashboard, reports, org structure, audit, settings | — | Agent B |

Why this order: masters before members before applications before payments. Every cycle's dependencies point strictly backwards. The previous order was unbuildable — the approval cycle needed fee resolution, membership terms and invoices that arrived two to three cycles later.

Everything a module needs — backend, customer UI, admin UI, tests — ships inside its own cycle. No "UI later" backlog.

## 3. Agent ownership

**Agent A — Member experience**
- `customer/` (entire Next.js app)
- Backend member-facing modules: `auth` (member half), `member`, `document`, `application` (member half), member views of `invoice`/`payment`/`event`/`notice`, `directory`, public endpoints
- Owns customer i18n copy, customer design-system components

**Agent B — Admin experience & operations core**
- `admin/` (entire React app)
- Backend operational modules: `auth` (admin half), `rbac`, `approval` engine, `membership-category`/`tier`/`fee`, `member-admin`, `invoice`, `payment`, `refund`, `renewal`, `event` (admin), `communication`, `notification` engine, `dashboard`, `report`, `audit`, `system-settings`
- Owns `prisma/` in every cycle except M3 and M9, seeds, jobs/cron

**Shared core (M0, written once, then frozen — changes need an ADR):** `helpers/encryption.ts`, `locales/`, `middleware/*` (incl. `express.json({verify})` raw-body capture, ADR-018), `utils/*`, `constant/*`, `db/prisma.ts`, `StorageAdapter`, audit helper, notification outbox + drain job (ADR-015), logging/redaction, `handleApiResponse`. Agent B writes it in M0; Agent A reviews before M1.

### Conflict prevention
| Risk | Rule |
|---|---|
| Same migration | One owner per cycle (table above); the other agent requests schema changes through the owner |
| Same shared file | Shared core is frozen after M0; edits require an ADR line and are made by the owner agent only |
| Same route file | Member routes and admin routes are separate files under the same module folder (`x.routes.ts` / `x.admin.routes.ts`) |
| Same UI component | Each app has its own `components/ui`; no cross-app imports |
| Duplicate business logic | Business rules live in services only; both frontends call the API. Any logic found in a frontend is a review failure |

## 4. Contract-freeze checklist (start of every cycle)

Before either agent writes code, the cycle's plan file must contain:
1. Prisma models + fields + indexes for that module (copied from `database-design.md`, adjusted if needed), **each model and field carrying its `///` doc-comment — the text that becomes the `COMMENT ON` (ADR-013)**.
2. Endpoint list with request/response DTOs and permission per endpoint.
3. i18n keys added.
4. Screens from `screen-inventory.md` in scope, per app.
5. Sentinel suite additions.
6. The migration owner's name.

## 5. Task template per cycle

| Slot | Agent A | Agent B |
|---|---|---|
| 1 | Consume frozen contract, scaffold customer screens with mocked service layer | Prisma models + migration + seed |
| 2 | Backend member-facing module (types → repository → service → controller → routes) | Backend admin module + engine logic |
| 3 | Wire customer UI to real API (encryption, i18n, states) | Wire admin UI to real API |
| 4 | Unit + integration tests for own endpoints | Unit + integration tests for own endpoints |
| 5 | Self-review vs Definition of Done | Extend Sentinel suite for the module |
| 6 | Fix Sentinel findings assigned to A | Fix Sentinel findings assigned to B |

## 6. M0 breakdown

Full task list lives in `modules/M0-foundation.md` (single source of truth — it now also covers the notification outbox, raw-body capture, observability, the storage adapter, the port fix and the git blocker). Summary: B owns backend shared core + identity schema + admin shell; A owns the customer shell, the shared `enc-dec` util, the UI primitives, the Sentinel rewire and the first backup rehearsal.

**Exit criteria:** all three apps run on ports 4000/3000/3001; encrypted round-trip proven from customer, admin and Sentinel; `prisma migrate dev` clean from scratch; `db:check-comments` zero; outbox drains a queued row; one restore rehearsed; lint/format/husky green.

## 6b. Dependency order between the two agents

Within a cycle the two agents are not symmetric. B usually lands schema and engine; A consumes it. The handoff is explicit so neither waits on a guess.

| Cycle | Must happen first | Then, in parallel | Blocking handoff |
|---|---|---|---|
| M0 | B: config, encryption, i18n, error core, identity migration | A: customer shell + Sentinel · B: outbox, jobs, observability, admin shell | B publishes `helpers/encryption.ts` format + envelope on day 1; A cannot write `enc-dec.ts` before that |
| M1 | B: RBAC schema + seeds + `authenticate`/`authorize` | A: member auth endpoints + screens · B: admin auth + shells | B publishes JWT claim shape + permission codes |
| M2 | B: masters schema + fee resolution service | A: public membership page | B publishes category/tier/fee DTOs |
| M3 | A: `Members` + documents schema (A owns this migration) | A: profile/KYC/customer · B: admin member mgmt + document verification | A publishes `Members` field list + document DTOs before B starts admin screens |
| M4 | B: application + approval + term + invoice schema, engine, transition guard | A: applicant stepper/tracker · B: approver queue + decisions | B publishes application field set, status enum and tracker DTO |
| M5 | B: payment schema + provider interface + success transaction | A: member pay flow · B: admin finance ops | B publishes `PaymentProvider` + payment status machine |
| M6 | B: term/reminder logic + jobs | A: member renewal screens · B: admin buckets | B publishes term status machine + grace rules |
| M7 | B: event schema + capacity/registration transaction | A: browse/register · B: admin event ops | B publishes registration status machine |
| M8 | B: notice schema + audience resolution | A: member notices/bell · B: composer + outbox UI | B publishes audience DTO + template codes |
| M9 | A: directory schema/indexes + field allowlists | A: public site + directory · B: admin visibility toggle | A publishes the public vs member field allowlist |
| M10 | B: everything (A has only a dashboard polish pass) | — | — |

Rule: the "must happen first" item is a **contract publication**, not a full implementation. B writes the types/DTOs and the migration, commits, tells A, and both proceed. A never blocks on B's business logic being finished.

## 7. Effort shape (indicative, not a commitment)

| Cycle | Backend | Customer UI | Admin UI | Notes |
|---|---|---|---|---|
| M0 | L | M | M | Highest leverage — do not rush |
| M1 | M | M | M | RBAC seeds gate everything |
| M2 | M | L | S | Upload + verification UX is the bulk |
| M3 | L | L | L | The heart of the product |
| M4 | M | S | L | Mostly admin |
| M5 | L | M | L | Money correctness > speed |
| M6 | S | S | M | Depends on M5 |
| M7 | M | M | M | Self-contained |
| M8 | M | S | M | Outbox + templates |
| M9 | S | L | S | Public/SEO surface |
| M10 | M | — | L | Reports + config |

## 8. Reporting

After every cycle the owning agents update: the module plan file (status, what shipped, what deviated), `implementation-status.md`, and `architecture-decisions.md` if anything changed. Sentinel's report path is pasted into the module file. Then, and only then, the cycle is presented for user approval.
