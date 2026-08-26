# Proposal → Requirements Verification

Purpose: prove that what is being built matches the signed proposal, and state exactly where that proof is incomplete.

## 1. Extraction status — RESOLVED

`docs/proposal.txt` supplied by the user on 2026-08-12 and read in full (195 lines). PV-1 is closed. Verification below is now against the **actual proposal text**, not an intermediary.

Earlier extraction attempts (Read tool, pypdf, manual zlib parse, Spotlight, dockerised poppler) all failed on subset-embedded fonts — recorded for future reference; use `proposal.txt`.

## 1b. What the proposal says that the module breakdown did NOT carry

These are contractual facts found only in the proposal. Each has been actioned.

| # | Proposal text | Impact | Action taken |
|---|---|---|---|
| P-1 | "All business/member data belongs to the client and **resides on the client's own hosting/cloud account**. Sarvadhi accesses it only as required for implementation and support." | Deployment target is **client-owned infrastructure**, not ours. Backup credentials, hosting account and data custody are the client's. | `deployment.md` §0 added; OQ-10/OQ-11 reframed — the client picks and owns the host |
| P-2 | "**Source code remains with Sarvadhi**; the client receives the deployed solution and agreed deliverables." | Repo ownership is Sarvadhi's; the client gets a deployment, not the repo | Recorded here and in `deployment.md` §0 |
| P-3 | "3 months of complimentary support included post go-live… Support runs **Mon–Sat 10:00–19:00 IST**, email and WhatsApp, **first response within 8 working hours**." | A warranty + support commitment exists. Needs a defect intake path and handover documentation | `deployment.md` §10 (handover + support) added |
| P-4 | "Defects in delivered scope reported within the 3-month support window are corrected at no cost. Warranty does **not** cover client-side infrastructure, third-party integrations or unauthorised modification." | Sharpens what "done" must mean per module; third-party (gateway/WhatsApp/accounting) failures are excluded | Reinforces the Definition of Done and the adapter strategy |
| P-5 | "Client nominates a single point of contact, **provides content/data (member categories, fee structure, branding assets)** in an agreed format, and gives **feedback or sign-off within five working days** of each milestone. **Delays in these inputs shift the delivery schedule.**" | The open questions in `assumptions.md` are contractually the client's inputs, and slow answers legitimately move the date | `implementation-plan.md` §1 rule 7; each module's approval checklist is the milestone sign-off |
| P-6 | "Responsive Design — The Member Portal will be built **mobile-responsive**… full functionality across desktop, tablet and mobile browsers." | Responsiveness of the member portal is a contractual deliverable, not a nicety | `requirements.md` FR-22; `design-system.md` breakpoints already mobile-first for customer |
| P-7 | Admin Portal item 5: "**Two-way sync** with cloud accounting platforms such as Refrens, Vyapar, Zoho Books for every invoice and payment." Plus "Accounting-synced, not double-entered — invoices and payments flow straight into Tally / Zoho Books / QuickBooks." | Accounting integration **is inside the signed proposal scope**. `CLAUDE.md` and the master instructions park it. | **Parked ≠ descoped.** `scope.md` now states it as deferred contractual scope requiring written change control (the proposal's own "Change Requests" clause) |
| P-8 | "Third-party subscription costs (payment gateway, WhatsApp API, accounting software, hosting, domain, SSL) — **client-borne**." | We do not procure gateway/WhatsApp/hosting accounts; the client does. Explains why OQ-4/OQ-5/OQ-10 are client decisions | Reflected in the decisions list |
| P-9 | "Refunds — **All payments are non-refundable**." | This is Sarvadhi's commercial term, **not** the association's member-refund policy. The admin Refunds module (Portal 2 item 4) stays in scope | Noted so nobody conflates the two |
| P-10 | "Public member directory (**if allow**)" | The proposal itself leaves directory publicity undecided | Confirms OQ-7 is a genuine open question, not an oversight |
| P-11 | **No delivery timeline appears anywhere in the proposal** — only milestone sign-offs and a 7-day validity on the offer | The "one-week MVP" originates solely from the master instructions, not the client contract | `planning-review.md` §8 and R-21 updated |
| P-12 | "Payment gateway linked invoicing" with no provider named | Confirms OQ-4 | Adapter strategy (ADR-008) already covers it |

Nothing in the proposal contradicts a technical decision already taken. Nothing in the proposal was missed by `module-breakdown.docx` at the **feature** level — the gaps were all commercial/operational terms, listed above.

## 2. Traceability — module breakdown → requirements → plan

| # | Module (breakdown §28) | Priority | `requirements.md` | Cycle | Screens | Status |
|---|---|---|---|---|---|---|
| 1 | Public Website | Core | FR-1 | M9 | C-01…C-05 | Covered |
| 2 | Authentication & Account | Core | FR-2 | M1 | C-06…C-09, A-01 | Covered |
| 3 | Membership Application | Core | FR-3 | M4 | C-11…C-13, A-03/04 | Covered |
| 4 | Approval Workflow | Core | FR-4 | M4 | A-03…A-06, A-33 | Covered |
| 5 | Member Profile & KYC | Core | FR-5 | M3 | C-14…C-17, A-13 | Covered |
| 6 | Membership Category / Tier | Core | FR-6 | M2 | A-10 | Covered — values blocked by OQ-2 |
| 7 | Member Management | Core | FR-7 | M3 | A-07…A-09 | Covered |
| 8 | Billing & Finance | Core | FR-8 | M4 (invoices) + M5 | C-19…C-22, A-14…A-19 | Covered |
| 9 | Payment Gateway | Core | FR-9 | M5 | C-20/21, A-16…A-18 | Covered behind an adapter — provider is OQ-4 |
| 10 | Membership Renewal | Core | FR-10 | M6 | C-18, C-23, A-20 | Covered — rules blocked by OQ-6 |
| 11 | Event Management | Core | FR-11 | M7 | C-24/25, A-21…A-24 | Covered |
| 12 | Communication | Core | FR-12 | M8 | C-26/27, A-25…A-28 | Covered — WhatsApp is OQ-5 |
| 13 | Member Directory | Core | FR-13 | M9 | C-05, C-28 | Covered — visibility is OQ-7 |
| 14 | RBAC & Permissions | Core | FR-14 | M1 (+M10 UI) | A-31/32 | Covered — matrix is OQ-1 |
| 15 | Hierarchy & Designations | Core | FR-15 | M10 | A-30 | Covered |
| 16 | Accounting Integration | Integration | FR-16 | — | — | **PARKED — intentionally not built** |
| 17 | Dashboard & Reports | Core | FR-17 | M10 | A-29 | Covered |
| 18 | Notifications & Automation | Cross-functional | FR-18 | M0 (outbox) + M8 | A-28, C-27 | Covered |
| 19 | Document / File Management | Supporting | FR-19 | M3 | C-14, A-12/13 | Covered |
| 20 | Audit / Activity History | Recommended | FR-20 | M0 + M10 | A-35 | Covered |
| 21 | System Config / Masters | Recommended | FR-21 | M2 + M10 | A-10…A-12, A-34 | Covered |

All 21 modules are accounted for. 20 are in scope; #16 is deliberately parked per `CLAUDE.md`, master instructions §19 and `scope.md`.

## 3. Out-of-scope list (breakdown §27) — confirmed excluded

Native mobile apps · marketing CMS beyond core public pages · hardware/RFID event check-in · legacy migration beyond basic import · multi-language UI (i18n plumbing is built; only `en` is populated) · third-party subscription costs.

## 4. Items the plan ADDS beyond the breakdown — declared, not smuggled

| Addition | Justification | Sanctioned by |
|---|---|---|
| Payload/response encryption | User instruction (Elvee parity) | ADR-004 |
| i18n message layer | User instruction | Architecture §6 |
| Mandatory DB comments | User instruction | ADR-013 |
| Audit log module | Breakdown §22 "Recommended"; approvals + money make it necessary | FR-20 |
| System settings / masters | Breakdown §23 "Recommended" | FR-21 |
| Notification outbox table + drain job | Delivery reliability for FR-18; prevents SMTP failures rolling back approvals | ADR-010 |
| Deployment / backup / observability / storage / webhook docs | Master instructions §20 security + operability; were missing | This review |

Nothing else was invented. Where the proposal is silent (fees, stages, gateway, WhatsApp, renewal rules, directory visibility), the plan records an Open Question rather than a guess — per `CLAUDE.md`.

## 5. Contradictions found between source documents

| # | Contradiction | Resolution |
|---|---|---|
| 1 | Breakdown §18 lists Tally/Zoho/QuickBooks in one section and Refrens/Vyapar/Zoho in another | Moot — accounting is PARKED. Recorded for whenever it is unparked |
| 2 | Master instructions target a "one-week MVP" while listing 21 modules and 25 planning deliverables | Master instructions §2 itself subordinates the week to correctness. Feasibility assessed in `planning-review.md` §7 |
| 3 | Skeleton `RULES.md` mandates raw SQL for all reads; maintainability argues otherwise | ADR-005 hybrid; `RULES.md` amended in M0 |
| 4 | Breakdown recommends an audit module; proposal does not list one | Adopted as FR-20, declared above |
| 5 | Breakdown says the public directory is "if allowed by the association"; plan assumed public | OQ-7 raised; no default assumed |

## 6. Verification gaps that remain

| ID | Gap | Class |
|---|---|---|
| PV-1 | ~~Proposal body text unverified~~ | **CLOSED** 2026-08-12 — `proposal.txt` supplied and verified in full |
| PV-2 | ~~Commercials unread~~ | **CLOSED** — read and actioned; see §1b. No SLA or data-migration commitment beyond "basic import" |
| PV-3 | The proposal contains no UI mockups (confirmed — the text has none and the deck is text/table based) | **CLOSED** — design is first-principles; theme direction now supplied by the user (ElevenLabs-style monochrome, `design-system.md`) |
| PV-4 | Accounting integration is contractual scope but parked for MVP | **OPEN — NEEDS DECISION.** Client must be told it is deferred, and a written change note recorded, or the delivery will be judged incomplete against the proposal |
| PV-5 | "Basic import" of legacy data is inside proposal scope ("beyond basic import" is what is excluded) | **OPEN — NEEDS DECISION.** A member CSV import utility is currently only an optional M10 item; confirm the client expects it |
