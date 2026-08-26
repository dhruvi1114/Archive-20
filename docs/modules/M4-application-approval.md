# M4 — Membership Application, Approval Workflow & Activation

**Status:** IN_PROGRESS (2026-08-13) · **Migration owner:** Agent B · **Blocking OQ:** ~~OQ-3~~ **answered** — role/permission-driven, configurable stages, super-admin-set resubmission limit (`approval-workflow.md` §2). **OQ-8 partially open** — approval must raise an invoice (confirmed), but the number format, the association's GSTIN and whether it issues tax invoices are still needed before anything can be issued to a real member · **Depends on:** M2 (fees), M3 (member record)

> Reordered by ADR-019. This cycle now owns the membership-term and invoice **schema and issuance**, because final approval must create them atomically. The payment side is M5.

## Goal
An applicant submits and always knows where they stand. Approvers act on a scoped queue, every decision is recorded, and final approval atomically produces an active-pending member with a code, a term and an invoice.

## Agent B — approval engine, activation, invoice issuance, admin
- Migration: `MembershipApplications`, `ApplicationDocuments`, `ApprovalWorkflows`, `ApprovalStages`, `ApprovalRequests`, `ApprovalActions`, `MembershipTerms`, `Invoices`, `InvoiceItems` + every CHECK/partial-unique from `database-design.md`. Seed the two workflows. All commented.
- `modules/approval`: transition guard table, stage resolution, queue scoping by `approver_role_id`, `SELECT … FOR UPDATE` locking, append-only history, profile-change-request approval (the M3 stub becomes real).
- Final-approval transaction exactly as `approval-workflow.md` §5: application → APPROVED, member → PENDING + `member_code`, `MembershipTerms` (PENDING_PAYMENT), `Invoices` + `InvoiceItems` from the M2 fee resolution, `Members.current_term_id`, status history, queued notifications, audit rows. All-or-nothing.
- `modules/invoice` (issuance half): numbering helper, issue, cancel, immutability after issue, PDF generation. Payment state transitions arrive in M5.
- Admin screens A-02 (queue populated), A-03…A-06, A-33.

## Agent A — applicant side
- `modules/application` member half: create draft (one open per user, DB-enforced; creates the `DRAFT` member per ADR-016), autosave patch, document upload, submit with server-side completeness validation, withdraw, resubmit after return, tracker payload in member vocabulary.
- Customer screens C-11, C-12, C-13, dashboard wiring on C-10, and the "approved — pay to activate" state pointing at the invoice (the pay button itself lights up in M5).

## Contracts frozen
Application field set + snapshot semantics · status enum + transition table · `ApprovalActions` shape · queue filters · tracker DTO · activation transaction's exact outputs · invoice numbering format.

## Self-test
`application` suite: draft → submit → stage 1 → stage 2 → final → member + code + term + invoice created in one transaction · forced failure mid-transaction leaves nothing behind · return → correct → resubmit · reject without remarks → 422 · two approvers racing → one 200, one 409 · approver without the stage role → 403 · no internal ids in member-facing payloads · missing fee config blocks approval with an actionable message.

## Definition of done
- Rollback proven by fault injection, not by inspection.
- Every action writes `ApprovalActions` + `AuditLogs`.
- Every member-facing status passes the four-line contract (`ux-principles.md` §2).
- Invoice totals are server-computed from `InvoiceItems`; no client input is trusted.

## Approval checklist
Stage count and approver roles (OQ-3) · return vs reject semantics · resubmission limit · invoice number format + GST treatment (OQ-8) · whether stage config must be editable in MVP (ADR-011).

## Decisions carried in from the M3 review (2026-08-13)
- Approval authority is **permission-driven**: whoever holds `application.approve` can approve. The `rbac.md` §3 matrix is the seeded default and can be re-seeded without code.
- Stage count and their owning roles are **data** (`ApprovalStages.approver_role_id`), not code.
- Resubmission limit is a **super-admin setting** (`SystemSettings.application.max_resubmissions`, `0` = unlimited), enforced server-side and surfaced to the applicant before they hit it.
- The stage-editor UI stays in M10 unless the user says otherwise; M4 seeds the stages.
- Terminal-state UI pattern established in M3: an illegal-but-plausible action keeps its button and earns a 409 that names both states; an action that is **permanently** impossible is disabled with the reason attached, never hidden.
