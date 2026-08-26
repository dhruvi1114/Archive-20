# Final Planning Review

Planning Agent, 2026-08-12. **Updated the same day** after the user supplied `docs/proposal.txt` and answered five decisions (§0). Reviewed: `CLAUDE.md`, master engineering instructions, module breakdown, the **full proposal text**, the existing backend skeleton, the Elvee reference implementation, `sarvadhi-sentinel`, and all 25 planning documents. No production code written.

Classification used: **BLOCKER** (work cannot correctly start/finish) · **NEEDS DECISION** (a business or infra choice only the user can make) · **RECOMMENDATION** (improves outcome; declining is reasonable).

---

## 0. User decisions recorded (2026-08-12)

| # | Decision | Effect on the plan |
|---|---|---|
| 1 | **Git added later** | B-1 downgraded from blocker to **accepted risk R-13**. Interim controls: strict per-cycle file ownership + a tar snapshot of the tree at each cycle boundary. Re-raise before the first deploy — a `prisma/migrations` history with no version control is the sharpest edge here |
| 2 | **Theme: ElevenLabs-style black & white** | `design-system.md` rewritten to a monochrome token set (neutral scale, hairline borders, black primary, desaturated status hues, dark tokens defined). UX-1 closed |
| 3 | **Complete the entire project** (not a one-week subset) | §8 revised: full 11-cycle delivery, ≈27–39 working days of build with two agents. Week-one subset is no longer the target |
| 4 | **Dev SMTP credentials later** | A-13: console transport in `local`, Mailhog/Ethereal in `dev`. Outbox, templates and drain job are fully exercised without real SMTP; swapping it in is env-only |
| 5 | **`docs/proposal.txt` supplied** | PV-1/PV-2/PV-3 closed. Full verification done — 12 contractual facts extracted, 2 new open items raised (PV-4 accounting, PV-5 basic import). See `proposal-verification.md` §1b |

---

## 1. Source consistency check

| Check | Result |
|---|---|
| Proposal ↔ module breakdown | **Verified in full** against `docs/proposal.txt`. Feature coverage matches at every point. The proposal carries 12 commercial/operational terms the breakdown omitted — all now captured (`requirements.md` §3b, FR-22, `proposal-verification.md` §1b). Two new open items: **PV-4 accounting is signed scope but parked**, PV-5 basic import. |
| Module breakdown ↔ `requirements.md` | Consistent. All 21 modules traced to FR-1…FR-21; #16 accounting is PARKED in three places. |
| Requirements ↔ `scope.md` ↔ module plans | Consistent after this review's resequencing. |
| Requirements ↔ `screen-inventory.md` | Consistent; 2 screens added (privacy policy, terms — DPDP, `security.md` §8). |
| Master instructions' 25 deliverables | All present, plus 9 added by this review. |
| CLAUDE.md constraints (stack, 2 coding agents, existing Self-Test Agent, accounting parked, Prisma migrations) | Honoured. |

**Contradictions found in source documents** (detail in `proposal-verification.md` §5): accounting vendor lists disagree between breakdown sections (moot — parked); "one-week MVP" vs 21 modules (§8 below); skeleton `RULES.md` raw-SQL-only vs maintainability (resolved, ADR-005); breakdown recommends an audit module the proposal does not list (adopted, declared); directory publicity assumed rather than asked (now OQ-7).

---

## 2. Final architecture review

**Sound and unchanged in shape.** Customer (Next.js) + Admin (React/Vite) → one Express API → Prisma → PostgreSQL. Business logic backend-only; layered Route → Middleware → Validation → Controller → Service → Repository.

Findings fixed in this review:

| # | Finding | Class | Resolution |
|---|---|---|---|
| A-1 | **Cycle order was unbuildable.** The approval cycle had to resolve a fee (2 cycles later), create a membership term (3 later) and issue an invoice (2 later). The application form's category/fee step needed masters that did not exist yet. | BLOCKER | Resequenced: masters → members → application/approval (owns term + invoice issuance) → payments. **ADR-019**, `migration-strategy.md`, all module files updated. |
| A-2 | **Notification delivery was scheduled after its first consumers.** Signup OTP (M1) and approval emails need an outbox that only appeared in M8. | BLOCKER | Outbox tables + drain job + `EmailChannel` moved to M0. **ADR-015**. |
| A-3 | **Member record only existed after approval**, so profile/KYC was unbuildable before the approval engine and required a field-copy step. | BLOCKER | `Members` row created at application start with status `DRAFT`. **ADR-016**; supersedes A-8. |
| A-4 | **Webhook raw body** would have to be added to frozen shared core in M5. | BLOCKER (latent) | `express.json({verify})` in M0. **ADR-018**. |
| A-5 | Framework/runtime versions unpinned — two agents would drift (Express 4 vs 5, Next 14/React 18 vs 15/19, Tailwind 3 vs 4). | BLOCKER | `versions.md`, **ADR-014**. |
| A-6 | Storage decision (OQ-10) was marked as blocking M0. | NEEDS DECISION → downgraded | `StorageAdapter` + local driver. **ADR-017**. OQ-10 now blocks staging, not coding. |
| A-7 | Port collision: skeleton `PORT=3000`, customer app also 3000. | BLOCKER (trivial) | Backend → 4000. `versions.md`. |

Remaining architectural risk accepted: in-process cron (ADR-009) requires exactly one instance with `ENABLE_JOBS=true`; stated in `deployment.md` §3.

---

## 3. Final database / schema review

**Schema is production-shaped.** 45 tables, explicit referential actions, CHECK constraints, partial uniques for soft delete, `Decimal(14,2)` money, no polymorphic FKs, no CSV id columns, transaction boundaries named per workflow, index list derived from real queries, and mandatory `COMMENT ON` (ADR-013).

| # | Finding | Class | Resolution |
|---|---|---|---|
| D-1 | Migration order had forward references (terms/invoices before their creating cycle) | BLOCKER | Rewritten `migration-strategy.md` order table; every dependency now points backwards |
| D-2 | `Members.category_id` was to be created nullable then tightened later | RECOMMENDATION | Removed — masters (M2) now precede members (M3); FKs correct on first creation |
| D-3 | `RenewalReminders.notification_id` referenced a table created two cycles later | BLOCKER | Fixed by ADR-015 (Notifications in M0) |
| D-4 | Prisma does not emit database comments | (user requirement) | ADR-013 + `db:check-comments` gate in pre-push, migration checklist and Sentinel `schema` suite |
| D-5 | Two agents on one migration timeline | BLOCKER (process) | One migration owner per cycle, named in each plan file; multi-file schema so agents edit different files; branch-per-cycle (needs OQ-12) |
| D-6 | `AuditLogs` must be immutable | RECOMMENDATION → adopted | Revoke UPDATE/DELETE from the app role; asserted in the `schema` suite |
| D-7 | Seeded fee/category data depends on OQ-2 | NEEDS DECISION | Seed files exist and stay empty until answered; approval refuses to issue a ₹0 invoice |

Open schema-adjacent decision: audit retention (OQ-13).

---

## 4. Final API review

`/api/v1`, member/admin/public path split, fixed success + error envelopes, i18n messages, pagination capped at 100, allowlisted sort/filter columns, idempotent money endpoints, permission documented per endpoint (`api-specification.md`).

| # | Finding | Class | Resolution |
|---|---|---|---|
| API-1 | Webhook endpoint had no hardened contract | BLOCKER | `payment-webhook-security.md`: raw-body HMAC (timing-safe), timestamp window, `(provider,event_id)` uniqueness, 200-on-duplicate, amount re-verified server-side, alerting on signature failures, reconciliation fallback |
| API-2 | Encryption bypass list was implied, not enumerated | RECOMMENDATION | Enumerated in `api-conventions.md` §2 (multipart, webhooks, health) |
| API-3 | Money on the wire as a number risks float drift in JS clients | RECOMMENDATION → adopted | 2-dp strings, server-computed totals |
| API-4 | Upload/download contract was thin | BLOCKER | `file-storage.md`: validation chain incl. magic-byte sniffing, UUID keys, path containment, authorised streaming, 404-not-403 |

---

## 5. Final UX / design review

`ux-principles.md` (four-line contract), `customer-user-journeys.md` (8 journeys with failure/recovery), `admin-user-journeys.md` (10), `information-architecture.md`, `design-system.md` (tokens, components, status→variant map), `screen-inventory.md` (32 customer + 36 admin, with required states).

| # | Finding | Class |
|---|---|---|
| UX-1 | Brand colour is a placeholder (`#0F5132`) | NEEDS DECISION — logo/brand assets from the client |
| UX-2 | Privacy policy + terms pages missing | RECOMMENDATION → added as C-31/C-32 (content owner = client, OQ-18) |
| UX-3 | If the proposal contains UI mockups they are unread (image pages) | RECOMMENDATION — share them if they exist; current design is first-principles |
| UX-4 | Member-facing vocabulary must never leak internal stage/workflow ids | (already enforced) — Sentinel asserts it in the `application` suite |

---

## 6. Final security review

Full detail in `security.md`. Position summary:

- **Encryption (ADR-004) is obfuscation, not a confidentiality boundary.** The key ships in the browser bundle by necessity. Accepted for Elvee parity, with conditions: HTTPS mandatory everywhere, authn/authz/validation always run after decryption, `decrypted_data` local-only, per-environment keys, no real secret ever named `NEXT_PUBLIC_*`. Static IV weakness (R-5) documented with a one-file upgrade path.
- Separate member/admin identity + JWT audiences; DB-revalidated permissions; 404-not-403 on cross-tenant reads; append-only approval and audit history; parameterised SQL with allowlisted sort columns; private files outside every web root behind an authorised stream.
- CORS must be restricted to real origins — **do not** copy Elvee's `origin: '*'`.
- Log redaction denylist; no OTP/token/KYC/decrypted payload ever logged.

| Open | Class |
|---|---|
| 2FA for SUPER_ADMIN / ACCOUNTS (OQ-16) | RECOMMENDATION |
| Upload virus scanning (OQ-17) | RECOMMENDATION |
| Rate-limit store when scaling (OQ-14) | NEEDS DECISION (later) |
| DPDP: privacy policy, retention, anonymised staging data (OQ-15, OQ-18) | NEEDS DECISION before go-live |

---

## 7. Final infrastructure review

Three documents that did not exist before this review: `deployment.md`, `backup-recovery.md`, `observability.md`.

| # | Finding | Class |
|---|---|---|
| I-1 | **Project is not under version control** (only Sentinel has a repo) | **BLOCKER — must be fixed before M0** (OQ-12) |
| I-2 | No backup or restore policy for a system holding KYC + financial records | BLOCKER → `backup-recovery.md`: nightly `pg_dump` + uploads archive, off-host copy, checksums, rehearsed restore, RPO/RTO stated, DB+uploads backed up as a pair |
| I-3 | No deployment topology, release or rollback procedure | BLOCKER → `deployment.md`: nginx + PM2 (VPS) or AWS variant, `migrate deploy` only, backup-before-migrate, rollback table, env inventory, pre-production checklist |
| I-4 | No alerting — job/backup/notification failures would be silent | BLOCKER → `observability.md` §6 alert table, `JobRuns` + outbox surfaced on the dashboard |
| I-5 | Log format/redaction/retention undefined | RECOMMENDATION → adopted in M0 |
| I-6 | Host, storage driver and SMTP provider unchosen (OQ-10) | NEEDS DECISION before staging — **not** before coding |
| I-7 | No CI | RECOMMENDATION — GitHub Actions sketch in `deployment.md` §8 |

---

## 8. Final scope review and schedule

Scope is unchanged and correct: 20 modules in, **accounting PARKED**, out-of-scope list intact. Nothing added except what the user required (encryption, i18n, DB comments), what the proposal contractually requires (FR-22 responsive member portal, NFR-1…8) and the operational documents above.

**One scope item needs a conversation, not a decision from me.** The proposal sells accounting integration (Admin Portal item 5: two-way sync with Refrens/Vyapar/Zoho Books; overview: flows into Tally/Zoho/QuickBooks). `CLAUDE.md` parks it. That makes it **deferred contractual scope, not descoped work** — the proposal's own Change Requests clause requires written agreement. If the client is not told, the delivery reads as incomplete against what they signed (R-22, PV-4).

**Schedule.** The user has confirmed the complete project. The proposal contains **no delivery date** — only milestone sign-offs within 5 working days and a 7-day validity on the offer (P-11). The "one-week MVP" exists only in the master instructions, which themselves subordinate the week to correctness.

| Cycle | Rough effort |
|---|---|
| M0 foundation | 3–4 days |
| M1 auth + RBAC | 2–3 days |
| M2 masters & fees | 1–2 days |
| M3 members, KYC, documents | 3–4 days |
| M4 application + approval + activation + invoicing | 4–6 days |
| M5 payments, refunds, reconciliation | 3–5 days |
| M6 renewal | 2 days |
| M7 events | 2–3 days |
| M8 communication | 2–3 days |
| M9 directory + public site | 2–3 days |
| M10 dashboard, reports, org, audit, settings | 3–4 days |
| **Build total** | **≈ 27–39 working days** with both agents |

Add on top: UAT and client content (categories, fees, page copy, branding), plus the go-live handover pack (`deployment.md` §10). Per NFR-6, **client input delays shift the schedule** — which is why every cycle lists its blocking questions up front and `implementation-status.md` records when each sign-off was requested and received.

## 9. Coding Agent A — responsibilities

**Owns:** the member experience end to end.

- `customer/` — the entire Next.js app: public pages (home, about, membership, events, directory, privacy, terms), auth screens, member shell, dashboard, application stepper + tracker, profile/KYC, invoices/payments, renewal, events, notices, notification feed, settings. All states from `screen-inventory.md`.
- Backend member-facing modules: `auth` (member half), `member`, `document`, `application` (member half), member views of invoices/payments/events/notices, `directory`, public endpoints.
- **Migration owner in M3** (members, contacts, addresses, documents, change requests) and **M9** (directory indexes).
- Shared UI primitives and the customer half of the design system; customer i18n copy.
- Sentinel rewire in M0 and the customer E2E suites thereafter.
- Backup script installation + the first rehearsed restore (M0).

**Never:** touches `prisma/` outside M3/M9; implements business rules in the frontend; edits shared core after M0 without an ADR.

---

## 10. Coding Agent B — responsibilities

**Owns:** the admin experience and the operational core.

- `admin/` — the entire React + Vite app: work queue, application review, member management, masters, billing/finance, renewals, events, communication, reports, RBAC/settings, audit.
- Backend shared core (M0): config, encryption, i18n, error handling, logging/redaction, audit helper, storage adapter, notification outbox + drain job, jobs/cron, health endpoints, raw-body capture.
- Backend operational modules: `auth` (admin half), `rbac`, masters/fees, `approval` engine, `member-admin`, `invoice`, `payment`, `refund`, `renewal`, `event` (admin), `communication`, `notification`, `dashboard`, `report`, `audit`, `system-settings`.
- **Migration owner in every cycle except M3 and M9**; owns seeds.
- Sentinel suite extensions for admin/API flows.

**Never:** implements member-portal screens; changes an approved API contract without republishing it to A; edits `customer/`.

---

## 11. Dependency order between the two agents

Full table in `implementation-plan.md` §6b. The rule: within each cycle, one agent **publishes a contract** (Prisma models + DTOs + status machine) before the other consumes it — publication, not full implementation, is the gate.

```
M0  B: config+crypto+i18n+errors ──▶ A: enc-dec, shells, Sentinel
M1  B: RBAC schema + guards      ──▶ A: member auth screens
M2  B: masters + fee resolver    ──▶ A: public membership page
M3  A: Members + document schema ──▶ B: admin member mgmt + verification
M4  B: application/approval/term/invoice schema + engine ──▶ A: stepper + tracker
M5  B: payment schema + provider + success txn ──▶ A: pay flow
M6  B: term/reminder logic       ──▶ A: renewal screens
M7  B: event schema + capacity txn ──▶ A: browse/register
M8  B: notice schema + audience  ──▶ A: notices + bell
M9  A: directory schema + field allowlist ──▶ B: admin visibility toggle
M10 B only (A: dashboard polish)
```

---

## 12. Final implementation plan

Unchanged in method, corrected in order: 11 cycles, one in flight at a time, contracts frozen before code, one migration owner per cycle, Sentinel at the end of every cycle, user approval before the next begins. Full detail in `implementation-plan.md`; per-cycle tasks, self-test assertions, DoD and approval checklists in `docs/modules/M0…M10`.

---

## 13. Final list of blockers

| # | Blocker | Blocks | Owner | Effort |
|---|---|---|---|---|
| ~~B-1~~ | ~~Project not under git~~ | — | **User decision: deferred.** Now accepted risk R-13 with tar-snapshot + file-ownership controls. Revisit before the first deploy | — |
| ~~B-2~~ | ~~Proposal unverified~~ | — | **CLOSED** — `proposal.txt` supplied and verified in full | — |
| B-3 | Permission matrix unsigned (OQ-1) | M1 seeds | User | Review `rbac.md` §3 |
| B-4 | Categories, tiers, fees, duration, eligibility (OQ-2) + required documents (OQ-9) | M2 | User/client | Client input |
| B-5 | Approval stages, approver roles, return/reject/resubmission rules (OQ-3) | M4 | User/client | Client input |
| B-6 | Invoice numbering format + GST treatment (OQ-8) | M4 | User/client | Client input |
| B-7 | Renewal reminder schedule, grace period, post-grace behaviour (OQ-6) | M6 | User/client | Client input |
| B-8 | Directory public or login-only + visible field list (OQ-7) | M9 | User/client | Client input |

| B-9 | **Accounting deferral not yet agreed in writing with the client** (PV-4) | go-live acceptance | User → client | One written change note |
| B-10 | "Basic import" of legacy member data may be expected (PV-5) | M10 | User → client | Confirm |

Deliberately **not** blockers, because an adapter absorbs them: payment gateway (OQ-4 → Manual/Mock providers, ADR-008), WhatsApp provider (OQ-5 → channel throws `NOT_CONFIGURED`, ADR-010), hosting/storage (OQ-10 → `StorageAdapter`, ADR-017).

---

## 14. Final list of decisions required from you

**Answered 2026-08-12** (§0): version control deferred · theme = ElevenLabs monochrome · complete project · SMTP later · proposal supplied.

**Still needed before M0 can start** — nothing technical. M0 is unblocked. Two commercial items should be raised in parallel because they affect acceptance, not code:
1. **Tell the client the accounting integration is deferred**, in writing, under the Change Requests clause (PV-4, R-22).
2. **Confirm whether "basic import" of existing member data is expected** (PV-5) — it sits inside the proposal's scope wording.
3. Client's **logo/wordmark** (the only place brand colour appears in a monochrome system) — needed by M9, not M0.

**Before the cycle that needs them**
5. Permission matrix sign-off (M1) · 6. Categories/tiers/fees/duration + required documents (M2) · 7. Approval stages and rules (M4) · 8. Invoice numbering + GST (M4) · 9. Payment gateway (M5, or stay on Manual) · 10. Renewal rules (M6) · 11. WhatsApp provider (M8, or email-only) · 12. Directory visibility and fields (M9).

**Before go-live**
13. Hosting + storage driver (OQ-10) · 14. Backup destination + credentials owner (OQ-11) · 15. WAL/PITR or accept a 24 h RPO (OQ-10b) · 16. Audit retention (OQ-13) · 17. Rejected-applicant document retention (OQ-15) · 18. Privacy policy + terms content (OQ-18).

**Recommendations you may decline**
19. 2FA for SUPER_ADMIN/ACCOUNTS (OQ-16) · 20. Upload virus scanning (OQ-17) · 21. Per-member storage quota (OQ-19) · 22. GitHub Actions CI · 23. Refund→membership-term policy (OQ-8b; MVP default: term untouched).

---

**Status: planning review complete, updated with the full proposal and your five decisions. No code written. M0 is unblocked — awaiting your go-ahead.**
