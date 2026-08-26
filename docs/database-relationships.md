# Database Relationships

## 1. Entity relationship map

```
Users 1──1 Members (primary_user_id)
Users 1──n MembershipApplications
Users 1──n AuthTokens / OtpCodes / PasswordResetTokens

AdminUsers n──n Roles           (AdminUserRoles)
Roles      n──n Permissions     (RolePermissions)
Roles      1──n ApprovalStages  (approver_role_id)

MembershipCategories 1──n MembershipTiers
MembershipCategories 1──n FeeStructures        MembershipTiers 1──n FeeStructures
MembershipCategories 1──n Members              MembershipTiers 1──n Members

Members 1──n MemberContacts / MemberAddresses / MemberDocuments / MemberStatusHistory
Members 1──n MembershipTerms      Members 1──1 current_term (Members.current_term_id → MembershipTerms)
Members 1──n Invoices             Members 1──n Payments
Members 1──n EventRegistrations   Members 1──n NoticeRecipients
Members 1──n MemberProfileChangeRequests
Members n──n Committees (CommitteeMembers, carries designation_id)

MembershipApplications 1──n ApplicationDocuments
MembershipApplications 1──1 ApprovalRequests (subject_type = MEMBERSHIP_APPLICATION)
MemberProfileChangeRequests 1──1 ApprovalRequests (subject_type = PROFILE_CHANGE_REQUEST)

ApprovalWorkflows 1──n ApprovalStages
ApprovalWorkflows 1──n ApprovalRequests
ApprovalRequests  1──n ApprovalActions       ApprovalStages 1──n ApprovalActions
AdminUsers        1──n ApprovalActions

Invoices 1──n InvoiceItems      Invoices 1──n Payments
Payments 1──1 Receipts          Payments 1──n Refunds
MembershipTerms 1──1 Invoices (membership_term_id)
EventRegistrations 1──1 Invoices (event_registration_id)
MembershipTerms 1──n RenewalReminders

Events 1──n EventRegistrations  EventRegistrations 1──1 EventAttendance

Notices 1──n NoticeAudienceRules / NoticeRecipients
NotificationTemplates 1──n Notifications (by template_code + channel + locale, soft ref)
Users/AdminUsers/Members 1──n Notifications

Committees 1──n Committees (parent_committee_id, self-referencing)
Designations 1──n CommitteeMembers
```

## 2. Referential actions — and why

| Relation | ON DELETE | ON UPDATE | Reason |
|---|---|---|---|
| Members.primary_user_id → Users | RESTRICT | CASCADE | A login cannot vanish while a member record depends on it |
| MemberContacts/Addresses/Documents → Members | CASCADE | CASCADE | Owned children, meaningless alone |
| Members.category_id → MembershipCategories | RESTRICT | CASCADE | Never orphan a member's category; deactivate the category instead |
| MembershipTiers.category_id → MembershipCategories | RESTRICT | CASCADE | Same |
| FeeStructures.category_id / tier_id | RESTRICT | CASCADE | Historic pricing must stay resolvable |
| MembershipApplications.user_id → Users | RESTRICT | CASCADE | Application history survives account deactivation (soft delete only) |
| MembershipApplications.member_id → Members | SET NULL | CASCADE | Application predates the member; keep the row if the member is purged |
| ApplicationDocuments → MembershipApplications | CASCADE | CASCADE | Owned children |
| *Documents.document_type_id → DocumentTypes | RESTRICT | CASCADE | Cannot delete a type still in use |
| ApprovalRequests.application_id → MembershipApplications | CASCADE | CASCADE | Approval exists only for its subject |
| ApprovalActions → ApprovalRequests | CASCADE | CASCADE | Owned history |
| ApprovalActions.admin_user_id → AdminUsers | RESTRICT | CASCADE | An approval must always name a real actor |
| ApprovalStages.approver_role_id → Roles | RESTRICT | CASCADE | Cannot delete a role wired into a live workflow |
| Invoices.member_id → Members | RESTRICT | CASCADE | Financial records are never orphaned |
| InvoiceItems → Invoices | CASCADE | CASCADE | Owned lines |
| Payments.invoice_id → Invoices | RESTRICT | CASCADE | Payment history outlives edits; cancel, never delete |
| Receipts.payment_id → Payments | RESTRICT | CASCADE | Legal record |
| Refunds.payment_id → Payments | RESTRICT | CASCADE | Legal record |
| MembershipTerms.member_id → Members | CASCADE | CASCADE | Terms belong to the member |
| Members.current_term_id → MembershipTerms | SET NULL | CASCADE | Pointer, not ownership (avoids circular delete) |
| RenewalReminders → MembershipTerms | CASCADE | CASCADE | Owned schedule |
| EventRegistrations.event_id → Events | RESTRICT | CASCADE | Cannot delete an event with registrations; cancel it |
| EventAttendance → EventRegistrations | CASCADE | CASCADE | Owned child |
| Notifications.user_id / admin_user_id / member_id | CASCADE | CASCADE | Outbox rows die with the recipient |
| NoticeRecipients → Notices / Members | CASCADE | CASCADE | Fan-out rows |
| CommitteeMembers.member_id → Members | RESTRICT | CASCADE | Office-bearer history must stay intact |
| Committees.parent_committee_id → Committees | SET NULL | CASCADE | Detach, do not cascade-destroy a subtree |
| AuditLogs.entity_id | *(no FK)* | — | Soft reference by design (ADR-006) |

## 3. Circular-reference handling

`Members.current_term_id ⇄ MembershipTerms.member_id` is the only cycle. Resolution: `MembershipTerms.member_id` is the owning FK (`CASCADE`); `Members.current_term_id` is a nullable pointer (`SET NULL`) set **after** the term row is inserted, inside the same transaction. Same pattern for `Invoices.membership_term_id` (invoice created first when the term is `PENDING_PAYMENT`, term links back on success).

## 4. Cardinality rules enforced in the DB, not just code

- One primary contact per member — partial unique index `(member_id) WHERE is_primary`.
- One open application per user — partial unique index `(user_id) WHERE status IN ('DRAFT','SUBMITTED','UNDER_REVIEW','RETURNED_FOR_CORRECTION')`.
- One registration per member per event — partial unique `(event_id, member_id) WHERE "deletedAt" IS NULL AND status <> 'CANCELLED'`.
- One active membership term per member — partial unique `(member_id) WHERE status = 'ACTIVE'`.
- One receipt per payment — unique `payment_id` on Receipts.
- One webhook event processed once — unique `(provider, event_id)`.
