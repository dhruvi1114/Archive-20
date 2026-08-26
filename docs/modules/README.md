# Module Plans

One file per cycle. Status lifecycle:

`PENDING → PLAN_CONFIRMED → IN_PROGRESS → SELF_TEST → FIXES → AWAITING_APPROVAL → APPROVED`

Rules: one module `IN_PROGRESS` at a time · contracts frozen before code · one migration owner per cycle · no `APPROVED` without a clean Sentinel run and the user's sign-off. Roll-up in `../implementation-status.md`. Order corrected by ADR-019 — every cycle's dependencies point strictly backwards.

| File | Module | Status |
|---|---|---|
| M0-foundation.md | Foundation & shared core | PENDING |
| M1-auth-rbac.md | Authentication, RBAC, app shells | PENDING |
| M2-masters-fees.md | Masters: categories, tiers, fees, document types | PENDING |
| M3-members-kyc.md | Member record, profile, KYC, member management | PENDING |
| M4-application-approval.md | Application, approval workflow, activation, invoice issuance | PENDING |
| M5-payments-finance.md | Payments, receipts, refunds, reconciliation, dunning | PENDING |
| M6-renewal.md | Membership renewal | PENDING |
| M7-events.md | Events | PENDING |
| M8-communication-notifications.md | Communication & notifications | PENDING |
| M9-directory-public-site.md | Directory & public website | PENDING |
| M10-dashboard-reports-org-audit.md | Dashboard, reports, org structure, audit, masters | PENDING |
