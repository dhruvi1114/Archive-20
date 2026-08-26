# Approval Workflow

## 1. Model

Approval is a domain workflow, not a status column. `ApprovalWorkflows` → `ApprovalStages` (ordered, each bound to an approver `Role`) → `ApprovalRequests` (one per subject) → `ApprovalActions` (immutable history).

Subjects (ADR-006, explicit FKs + CHECK): `MEMBERSHIP_APPLICATION`, `PROFILE_CHANGE_REQUEST`.

## 2. Workflow — role-driven and configurable (OQ-3 answered 2026-08-13)

**User decision:** who may approve, and the shape of the flow, are **defined by roles and permissions**, not hard-coded. That is what the schema already models — `ApprovalStages.approver_role_id` binds each stage to a role, and `application.approve` is the permission that grants the act. Consequences, now settled:

| Question | Answer |
|---|---|
| Who can approve a membership? | Whichever role holds `application.approve`. The matrix in `rbac.md` §3 is the **default**, not a hard rule: granting that permission to ADMIN makes ADMIN an approver, with no code change |
| How many stages, and who owns each? | Rows in `ApprovalStages`, each pointing at a role. Adding or removing a stage is a data change |
| Can an applicant resubmit after a return? | Yes |
| How many times? | A limit the **super admin** sets — `SystemSettings.application.max_resubmissions` (`0` = unlimited). Enforced in the service, surfaced to the applicant before they hit it |

**Still to decide (does not block M4's engine):** whether the stage editor is a screen in M4 or stays M10. The engine reads configuration from day one either way; only the editing UI is in question. Recommendation: seed the stages in M4, ship the editor in M10 with the rest of the configuration screens — a workflow builder is a week of UI that the federation will use approximately twice.

## 2b. Seeded default workflow — `MEMBERSHIP_APPROVAL`

| Seq | Stage | Approver role | Can return | Final |
|---|---|---|---|---|
| 1 | Document Verification | ADMIN | ✔ | — |
| 2 | Committee Review | APPROVER | ✔ | — |
| 3 | Final Approval | SUPER_ADMIN | ✔ | ✔ |

`PROFILE_CHANGE_APPROVAL`: single stage, approver role ADMIN, final.

Stages are seeded rows; the engine reads them. Changing the number of stages is a data change, not a code change (ADR-011).

## 3. Application status machine

```
DRAFT ──submit──▶ SUBMITTED ──first stage picked up──▶ UNDER_REVIEW
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │ return                   │ approve (non-final)      │ reject
        ▼                          ▼                          ▼
RETURNED_FOR_CORRECTION      UNDER_REVIEW (next stage)     REJECTED (terminal)
        │ resubmit                  │ approve (final)
        └──────────▶ SUBMITTED      ▼
                                  APPROVED (terminal) ──▶ Member activated
DRAFT|SUBMITTED|UNDER_REVIEW|RETURNED ──withdraw──▶ WITHDRAWN (terminal)
```

### Allowed transitions (enforced in `ApprovalService` + DB CHECK)

| From | Action | Actor | To |
|---|---|---|---|
| DRAFT | submit | owner member | SUBMITTED |
| SUBMITTED | (auto on first admin open) | admin at stage 1 | UNDER_REVIEW |
| UNDER_REVIEW | approve (stage not final) | admin holding stage role + `application.approve` | UNDER_REVIEW (stage+1) |
| UNDER_REVIEW | approve (stage final) | as above | APPROVED |
| UNDER_REVIEW | return | admin holding stage role + `application.return` | RETURNED_FOR_CORRECTION |
| UNDER_REVIEW | reject | admin holding stage role + `application.reject` | REJECTED |
| RETURNED_FOR_CORRECTION | resubmit | owner member | SUBMITTED (stage resets to 1 unless the stage set `return_to_stage`) |
| DRAFT / SUBMITTED / UNDER_REVIEW / RETURNED | withdraw | owner member | WITHDRAWN |
| APPROVED / REJECTED / WITHDRAWN | * | — | **no transition** (409) |

Every other combination → `409 INVALID_STATE_TRANSITION`.

## 4. Rules

1. **Remarks are mandatory** for `reject` and `return`; optional for `approve`.
2. **Every action writes an `ApprovalActions` row** with actor, stage, from_status, to_status, remarks, timestamp. That table is append-only (no UPDATE/DELETE grant).
3. **Queue scoping**: an admin sees a request in their queue only if one of their roles equals the current stage's `approver_role_id` (or they are super admin).
4. **Concurrency**: the action handler locks the `ApprovalRequests` row (`SELECT … FOR UPDATE`) inside the transaction; a second approver acting simultaneously gets 409, not a double-advance.
5. **Resubmission**: `resubmission_count` increments; document re-uploads create `version + 1` rows rather than overwriting.
6. **SLA**: `ApprovalStages.sla_hours` is recorded and surfaced as an "overdue" badge in the admin queue. No auto-escalation in MVP.

## 5. Final approval transaction (atomic)

```
BEGIN
  lock ApprovalRequests row
  guard: status = OPEN, current stage is final, actor authorised
  insert ApprovalActions (APPROVE, → APPROVED)
  update ApprovalRequests  status = APPROVED, closed_at = now()
  update MembershipApplications status = APPROVED, decided_at = now()
  update Members (the DRAFT row created at application start, ADR-016) → status = PENDING
  generate member_code (sequence + unique constraint)
  insert MembershipTerms (NEW, valid_from, valid_till per category duration) → PENDING_PAYMENT
  insert Invoices + InvoiceItems from the effective FeeStructure
  update Members.current_term_id
  insert MemberStatusHistory (→ PENDING)
  insert Notifications (EMAIL + IN_APP: application approved, invoice due)
  insert AuditLogs (application.approved, member.created, invoice.issued)
COMMIT
```

Member becomes `ACTIVE` only when the membership invoice is paid (M5), or immediately if the fee is zero. Failure at any step rolls the whole thing back — no half-approved member.

## 6. Notifications emitted

| Event | To | Channels |
|---|---|---|
| Application submitted | member + stage-1 approver role | IN_APP, EMAIL |
| Stage approved (non-final) | member | IN_APP |
| Returned for correction | member (with remarks) | IN_APP, EMAIL |
| Rejected | member (with remarks) | IN_APP, EMAIL |
| Approved | member (+ invoice link) | IN_APP, EMAIL |
| Profile change decided | member | IN_APP |

## 7. What the UI must show at every point

Per master instructions §8 — current state, required action, next step, expected result:

| Application status | Member sees | Admin sees |
|---|---|---|
| DRAFT | "Not submitted — complete section X" + Submit CTA | not in queue |
| SUBMITTED | "Submitted on <date>. Waiting for Document Verification. Typically 2 working days." | in stage-1 queue, badge "New" |
| UNDER_REVIEW | "Under review — stage 2 of 3 (Committee Review)" + stage timeline | actionable if role matches stage |
| RETURNED_FOR_CORRECTION | remarks quoted verbatim + exactly which fields/documents to fix + Resubmit CTA | read-only until resubmitted |
| APPROVED | "Approved. Pay ₹X by <due date> to activate membership." + Pay CTA | closed, in member record |
| REJECTED | reason + who to contact | closed, reason on record |
