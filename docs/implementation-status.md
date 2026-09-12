# Implementation Status

Single source of truth for where the build is. Updated at the end of every cycle by the owning agents. Statuses: `PENDING` · `PLAN_CONFIRMED` · `IN_PROGRESS` · `SELF_TEST` · `FIXES` · `AWAITING_APPROVAL` · `APPROVED`.

_Last updated: 2026-08-31 — **M0–M4 built. M5 and M7 were built but this table still said PENDING; corrected below. M9 directory built, awaiting browser verification.** Git is now in use (four repositories: root docs, `backend/`, `admin/`, `customer/`), so the tar-snapshot control from August is superseded._

> **Read the statuses below with care.** Between 2026-08-18 and 2026-08-31 this
> table was not updated while work continued, and it claimed three modules were
> pending that were in fact built. The rows were corrected on 2026-08-31 against
> the code on disk rather than against memory. If a row here disagrees with the
> repository, trust the repository and fix the row.

| Cycle | Module | Status | Migration owner | Blocking OQ | Sentinel report | Approved on |
|---|---|---|---|---|---|---|
| M0 | Foundation & shared core | **APPROVED** | B | none | `smoke_2026-08-12-08-41-47_pass.md` PASS | 2026-08-12 |
| M1 | Auth, RBAC, app shells | **APPROVED** | B | OQ-1 accepted as seeded | `smoke_2026-08-12-11-59-45_pass.md` PASS | 2026-08-13 (user tested the auth flow) |
| M2 | Masters: categories, tiers, fees, document types | **APPROVED** | Planning Agent (inline) | OQ-2, OQ-9 still open — seeds intentionally empty | `smoke_2026-08-13-05-31-54_pass.md` PASS | 2026-08-13 (accepted on instruction to start M3) |
| M3 | Member record, profile, KYC, member management | **APPROVED** | Planning Agent + Agents A/B | OQ-15 (retention) — before go-live | `smoke_2026-08-13-09-04-03_pass.md` PASS | 2026-08-13 (user tested all cases) |
| M4 | Application, approval, activation, invoice issuance | **AWAITING APPROVAL** (2026-08-18) | Planning Agent (engine) + Agents A/B (UI) | OQ-3 answered; OQ-8 partial — GSTIN/tax-invoice still needed before real issuance | Sentinel 11/11 suites PASS incl. new `application` suite (25 checks); customer + admin driven in a real browser | Five defects found in verification, all fixed — see §M4 notes |
| M5 | Payments, receipts, refunds, reconciliation | **BUILT** (invoices, payments, receipt/invoice PDFs) — reconciliation and refunds screens still placeholders | B | OQ-4 (adapter covers it) | — | — |
| M6 | Membership renewal | **IN_PROGRESS** — code complete (Tasks 1–14, 17–18 built and reviewed); self-test (Sentinel `renewal` suite, Task 15) pending | B | ~~OQ-6~~ **answered 2026-09-10**; per-plan renewal amounts (A2) block billing, not the build | — | — |
| M7 | Events | **BUILT** — 29 backend files incl. 12 test files; admin event, registration and payment screens | B | — | — | — |
| M8 | Communication & notifications | PENDING | B | OQ-5 (adapter covers it) | — | — |
| M9 | Directory & public website | **BUILT, unverified in a browser** — News shipped earlier; member directory built 2026-08-31 (38 tests). Public homepage in progress on the `feature/public-homepage-*` branches | A | ~~OQ-7~~ **answered 2026-08-31: members-only** | — | — |
| M10 | Dashboard, reports, org, audit, settings | IN PROGRESS | B | OQ-13 | — | Saved reports + audit log screen delivered; dashboard tiles, roles/staff tabs, org structure outstanding |

## Planning deliverables

| Document | Status |
|---|---|
| requirements.md | ✅ |
| architecture.md | ✅ |
| architecture-decisions.md | ✅ |
| database-design.md | ✅ |
| database-relationships.md | ✅ |
| migration-strategy.md | ✅ |
| database-indexes.md | ✅ |
| api-specification.md | ✅ |
| api-conventions.md | ✅ |
| rbac.md | ✅ (matrix pending sign-off — OQ-1) |
| approval-workflow.md | ✅ (stages pending sign-off — OQ-3) |
| billing-payment.md | ✅ |
| notification-architecture.md | ✅ |
| ux-principles.md | ✅ |
| customer-user-journeys.md | ✅ |
| admin-user-journeys.md | ✅ |
| information-architecture.md | ✅ |
| design-system.md | ✅ |
| screen-inventory.md | ✅ |
| testing-strategy.md | ✅ |
| implementation-plan.md | ✅ |
| implementation-status.md | ✅ |
| scope.md | ✅ |
| assumptions.md | ✅ |
| risks.md | ✅ |
| modules/M0–M10 plan files | ✅ (all PENDING, resequenced per ADR-019) |
| versions.md | ✅ (added by planning review) |
| deployment.md | ✅ (added by planning review) |
| backup-recovery.md | ✅ (added by planning review) |
| observability.md | ✅ (added by planning review) |
| security.md | ✅ (added by planning review) |
| payment-webhook-security.md | ✅ (added by planning review) |
| file-storage.md | ✅ (added by planning review) |
| proposal-verification.md | ✅ (added by planning review — PV-1 open) |
| planning-review.md | ✅ (added by planning review) |
| client-decisions.md | ✅ (2026-08-12 — client-facing decision pack, plain language, ready to forward) |

## Open items

**M0 is unblocked.** User decisions of 2026-08-12: git deferred (R-13 accepted risk), theme = ElevenLabs monochrome, complete project confirmed, SMTP later (console/Mailhog interim), proposal supplied and verified.

Blocking later cycles: ~~OQ-1 (M1)~~ *(carried into M1 by user decision — the proposed matrix in `rbac.md` §3 is seeded as the working default; permissions are seed data, so a change is an upsert, not a migration)* · OQ-2 + OQ-9 (M2) · OQ-3 + OQ-8 (M4) · ~~OQ-6 (M6)~~ *(answered 2026-09-10 — renewal invoice raised 15 days before expiry; reminders at 15/7/3 days and on the expiry date; new `PAID_UPCOMING` term status for early payment; renewal basis as selected in System Settings; price from the member's own fee plan; after 30 days' grace the member is `EXPIRED`, not suspended. See `modules/M6-renewal.md`.)* · ~~OQ-7 (M9)~~ *(answered 2026-08-31 — the member directory is members-only: no public list, no public profile, no public search. Access requires a signed-in user whose own company is ACTIVE, not merely a login. See `client-decisions.md` D1 and `docs/specs/2026-08-31-member-directory.md`.)* · OQ-13 (M10).
Absorbed by adapters, not blocking: OQ-4 gateway, OQ-5 WhatsApp, OQ-10 hosting/storage.
Commercial, raise in parallel: **PV-4 — the client must be told in writing that accounting integration is deferred** (it is inside the signed proposal; suggested wording drafted in `client-decisions.md` §G1); PV-5 — confirm whether basic member-data import is expected (§G2).

**`client-decisions.md` collects every outstanding client input in one page**, grouped by when it becomes blocking. Sending it early is the cheapest schedule protection available — per the proposal, input delays legitimately shift delivery dates.

## Change log

| Date | Change | By |
|---|---|---|
| 2026-08-11 | Planning phase complete; 25 planning docs + 11 module plans created; 4 architecture decisions locked with the user (DB naming, hybrid reads, encryption+envelope, module sequencing) | Planning Agent |
| 2026-08-12 | ADR-013 added — mandatory `COMMENT ON` for every table and column, enforced by `npm run db:check-comments` in husky pre-push and the new Sentinel `schema` suite | Planning Agent |
| 2026-08-12 | Planning review: 9 documents added (versions, deployment, backup-recovery, observability, security, payment-webhook-security, file-storage, proposal-verification, planning-review). Cycle order corrected (ADR-019) after finding a dependency inversion; notification outbox moved to M0 (ADR-015); member record created at application start (ADR-016); storage adapter (ADR-017); raw-body capture (ADR-018); versions pinned (ADR-014). New risks R-13…R-21, new open questions OQ-11…OQ-19 | Planning Agent |
| 2026-08-12 | Full proposal text supplied and verified — 12 contractual terms extracted into FR-22 + NFR-1…8; accounting confirmed as **signed scope now deferred** (PV-4); basic import raised (PV-5). User decisions: git deferred (R-13 accepted), ElevenLabs monochrome theme (`design-system.md` rewritten), complete project confirmed (schedule ≈27–39 build days), SMTP later (console/Mailhog interim). New risks R-22…R-25. M0 unblocked | Planning Agent |
| 2026-08-12 | **M0 delivered.** Backend shared core (encryption, i18n, envelope, errors, config precedence, audit, storage, outbox + drain, jobs, observability, health/ready), identity schema (11 tables / 106 columns, every one commented), seeds (39 permissions / 4 roles / 96 grants), `db:check-comments` gate; customer Next 14 shell + admin Vite shell on the monochrome token set; Sentinel de-Elveed with `crypto` + `schema` suites; backup script + first restore rehearsal PASS. Three real bugs found and fixed in-cycle (latin1/UTF-8 crypto mismatch across apps ×2, env-precedence shadowing). ADR-020…024 recorded. Sentinel: PASS | Planning Agent + Agents A/B |
| 2026-08-12 | **M1 delivered.** Member + admin auth, RBAC with DB-revalidated permission cache, `AuthTokens`/`OtpCodes`/`PasswordResetTokens` migration, customer auth screens + route guard, admin login + permission-aware nav, Sentinel `auth`/`rbac` suites (37 checks) with all four roles covered. Both coding agents were stopped mid-cycle by the user; the Planning Agent verified the work, fixed the remaining defects inline and ran the gate. One real security bug fixed (signup phone-number enumeration), two Sentinel assertion defects fixed (one false FAIL, one false PASS). Schema: 14 tables / 134 columns, all commented. Sentinel: PASS | Planning Agent |
| 2026-08-13 | **M1 APPROVED** by the user after testing the authentication flow end to end. Post-approval UI corrections landed in the same session: admin `Layout` tokens (AntD's `#001529` navy header removed), shared `PageHeader`, card footer alignment, calmed alerts; customer four-line-contract panels removed from all five auth screens, form error summary defaulted off with focus-first-error, required copy trimmed to one word. Root causes fixed in `ux-principles.md` §2/§5 and `design-system.md` §5b so the patterns cannot recur | Planning Agent |
| 2026-08-13 | **M2 delivered.** Membership catalogue: 4 tables (18/181 commented), `modules/masters`, admin screens A-10/A-11/A-12, public membership page, Sentinel `masters` suite (13 assertions). Six defects found and fixed in-cycle, three of them real product bugs — a router-wide RBAC guard that blocked other modules' routes, an uncommented column the ADR-013 gate caught, and an exclusion violation surfacing as 500 instead of 409. Seeds deliberately empty pending OQ-2/OQ-9. Sentinel: PASS (9 suites) | Planning Agent |
| 2026-08-13 | Admin theming pass against the `theming-admin-black-white` skill: palette retargeted (CTA `#262626` not `#0a0a0a`, sidebar `#fafafa`, universal semantic pairs incl. blue `info`), operator density (13px body / 11px uppercase table headers / 18px titles), 56px lining shared by the sidebar logo row and header, identity moved to the sidebar footer, page title moved into the header with `PageHeader` keeping a visually-hidden `h1`, table chrome to the tables.md contract, 6px scrollbars, near-black focus rings. Sentinel: PASS (9 suites) | Planning Agent |
| 2026-08-13 | **M3 delivered.** Member record, profile, KYC documents and member management: 6 tables (24/259 commented), `modules/member` + `modules/document` with magic-byte upload validation and versioned re-upload, customer profile/KYC/contacts/addresses/dashboard, admin member list + detail + status dialogs + document verification, Sentinel `profile` suite (36 checks). Backend built inline; UI dispatched to two coding agents. Six defects fixed in-cycle including missing foreign keys caught pre-migration, a browser-blocking CORS design smell replaced with token-claim audience routing, and a storage-key leak. Sentinel: PASS (10 suites) | Planning Agent + Agents A/B |
| 2026-08-13 | **M3 APPROVED** after the user tested every case. Terminal-state UI shipped on request: status actions disable (never hide) once a membership is TERMINATED, with the reason attached. Invoice number format answered — `IN202603001` (`IN` + year + calendar quarter + 3-digit sequence restarting each quarter); implemented and proven unique under 10 concurrent allocations. OQ-3 answered: approval is permission-driven, stages are role-bound data, resubmission limit is a super-admin setting. 375px design pass deferred to a dedicated cycle | Planning Agent |
| 2026-08-18 | **M4 built and self-tested.** Application, three-stage approval, activation (member code + term + invoice in one transaction), 9 tables. Backend engine built inline; UI by Agents A/B, both of whom stopped before verifying their work in a browser. The Planning Agent finished the Sentinel `application` suite (25 checks, incl. reading the activation straight from the DB) and drove customer + admin through a real browser. **Five defects found in verification, all fixed:** (1) `validateRequest` replaces `req.params` and zod strips unnamed keys, so `idParamSchema` silently deleted `documentId` — application document **verify, remove and download all returned 500**; stage 1 *is* document verification, so the stage was unusable. Fixed with `documentIdParamSchema`; every multi-param route audited. (2) No download route was wired for application documents, and the admin shipped an explanatory panel in its place — a reviewer could not open the file they were asked to verify. Route nested under the application so the two id spaces cannot collide; panel replaced with an open action. (3) `getOrCreateOwnMember` raced itself on first page load (two reads, two inserts, unique violation surfaced as 409); now catches the violation and returns the winner's row. (4) `MemberShell` rendered the signed-in name during SSR, so React discarded the server tree and re-rendered the whole root — name held back until hydration. (5) The stepper marked *any* incomplete step as an error, so a brand-new draft opened with a red ✕ on a step nobody had reached; errors now only apply to steps already passed. Also fixed: the blocking list showed `Gst certificate` for outstanding documents because names were read from uploaded rows, which by definition do not exist yet. Backend prettier drift across M0–M4 cleared (lint gate was red). Sentinel: PASS (11 suites) | Planning Agent |
| 2026-09-10 | **M6 renewal plan updated; OQ-6 answered by the user.** Renewal term + invoice raised 15 days before expiry (new setting `membership.renewal_notice_days`), due on the expiry date; reminders at 15/7/3 days and on the expiry date; new `PAID_UPCOMING` term status so an early payment activates on the start date (one-active-term-per-member index); renewal basis as selected in System Settings; price from the member's own fee plan; short 31 March term for monthly/quarterly plans under financial year accepted. Double-billing guard planned as a partial unique on `(member_id, valid_from)` excluding `CANCELLED`. Updated `modules/M6-renewal.md` and `renewal-module-summary.md`. Docs only — no code | Planning Agent |
| 2026-09-10 | **M6 renewal built** (Tasks 1–14, 17–18): admin endpoints `/admin/renewals/summary`, `/admin/renewals` (bucketed, paginated) and `/admin/renewals/run` (`renewal.view`/`renewal.manage`); member endpoints `/membership/me/term`, `/terms`, `/renewal/plans`, `/renewal/plan`, `/renewal/decline`, `/renewal/resume`; hourly `membership.renewal` job (close → start paid-ahead → expire past grace → raise invoices at T-15 → remind); `membership.renewal_reminder` (T-15/T-7/T-3/T-0) and `membership.expired` (on grace end) notifications; admin screen A-20 (`/renewals`, Due Soon/In Grace/Expired tabs) and customer C-18/C-23 (`/application/membership`, no new nav item, plus a renewal banner above every member screen). `POST /membership/me/renew`, `/admin/renewals/:memberId/initiate` and `/admin/renewals/:termId/extend-grace` dropped, never built, per plan. New setting `membership.renewal_notice_days` (seeded 15) is not surfaced on the System Settings screen, per user decision. Built, uncommitted; Sentinel `renewal` suite (Task 15, self-test) pending | Planning Agent |
