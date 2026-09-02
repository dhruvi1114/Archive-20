# M10 — Dashboard, Reports, Org Structure, Audit & Masters

**Status:** PENDING · **Migration owner:** Agent B · **Blocking OQ:** — · **Depends on:** all prior cycles

## Goal
Staff can see the state of the association, prove who did what, structure the office bearers, and configure the system without a developer.

## Agent B — backend + admin
- Migration: `Designations`, `Committees`, `CommitteeMembers`, plus any report views/materialised views justified by `EXPLAIN`.
- `modules/dashboard`: summary (total/active members, pending approvals by stage, revenue collected in range, renewals due, event stats) — one query per tile, all indexed, cached 60 s.
- `modules/report`: members by category/status, revenue by period, renewals due, event attendance. **Delivered as SAVED reports** (`docs/specs/2026-09-02-saved-reports.md`): a report is generated once into `GeneratedReports` with the filters that produced it stored as `{id, name}` pairs, listed, and downloadable again later. XLSX only — a Summary sheet stating the filters before any figure, plus a Detail sheet when the breakdown was asked for. Deferred by decision: background generation for large results, and a per-member "Member Statement" report.
- `modules/organisation`: designations, committees (self-referencing), chapter structure, committee membership with term dates and overlap warnings.
- `modules/audit`: audit log query API (entity, actor, action, date range) + the History tab data used by member/application/invoice screens.
- Masters + settings UI: document types, notification templates (M8), system settings, roles/permissions matrix, admin users.
- Admin screens A-29…A-35.

## Agent A — customer effects
- Member dashboard final pass: real counts, correct next-action ordering, all empty/loading states verified against `ux-principles.md`.

## Contracts frozen
Dashboard tile definitions (exact SQL semantics of each number) · report parameter + column sets · audit query filters · settings key list and value types.

## Self-test
`reports` suite: each dashboard number matches an independently computed fixture value; date-range boundaries inclusive/exclusive as documented; export row count matches the on-screen count; audit log returns rows for a known action with correct before/after; last-super-admin removal blocked; role bound to a live approval stage cannot be deleted; committee term overlap warns.

## Definition of done
- No dashboard number is computed in the frontend.
- Reports run within budget on the seeded dataset (≥5k members, ≥20k invoices) with `EXPLAIN` verified.
- `AuditLogs` has no UPDATE/DELETE grant for the app role (verified by attempting one).
- Every configurable value used by earlier modules is editable here rather than hardcoded.

## Approval checklist
Report list + columns the association actually needs · dashboard tiles · designation/committee structure of the federation · retention period for audit logs.
