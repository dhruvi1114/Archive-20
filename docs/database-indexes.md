# Database Indexes

Rule: every index below exists because a listed query needs it. No speculative indexes. Composite column order follows equality-first, then range, then sort.

## Identity

| Table | Index | Query it serves |
|---|---|---|
| Users | `U(email) WHERE "deletedAt" IS NULL` | login, signup duplicate check |
| Users | `U(phone) WHERE phone IS NOT NULL AND "deletedAt" IS NULL` | phone login/duplicate |
| Users | `(status, "createdAt" DESC)` | admin user list filter |
| AdminUsers | `U(email) WHERE "deletedAt" IS NULL` | admin login |
| AuthTokens | `U(token_hash)` | refresh lookup |
| AuthTokens | `(user_id, revoked_at)` / `(admin_user_id, revoked_at)` | session list, logout-all |
| AuthTokens | `(expires_at)` | prune job |
| OtpCodes | `(identifier, purpose, expires_at DESC)` | OTP verify |
| RolePermissions | `U(role_id, permission_id)` + `(permission_id)` | permission set load, reverse lookup |
| AdminUserRoles | `U(admin_user_id, role_id)` | token claim build |

## Membership

| Table | Index | Query |
|---|---|---|
| Members | `U(member_code) WHERE "deletedAt" IS NULL` | code lookup |
| Members | `(status, category_id, "createdAt" DESC)` | admin member list (default filter + sort) |
| Members | `(category_id, tier_id)` | category/tier reports |
| Members | `U(primary_user_id)` | "my member" resolution on every member request |
| Members | `U(gst_number) WHERE gst_number IS NOT NULL AND "deletedAt" IS NULL` | duplicate KYC guard |
| Members | `U(iec_code) WHERE iec_code IS NOT NULL AND "deletedAt" IS NULL` | duplicate KYC guard |
| Members | GIN `to_tsvector('simple', company_name \|\| ' ' \|\| coalesce(legal_name,''))` | directory + admin search |
| Members | `(directory_visible, status)` | public directory list |
| MembershipTerms | `(member_id, valid_till DESC)` | current term, renewal history |
| MembershipTerms | `(status, valid_till)` | renewal sweep, expiring-soon dashboard |
| MembershipTerms | `U(member_id) WHERE status='ACTIVE'` | single active term |
| MemberStatusHistory | `(member_id, changed_at DESC)` | member timeline |
| FeeStructures | `(category_id, tier_id, fee_type, effective_from DESC)` | fee resolution at invoice time |

## Applications & approvals

| Table | Index | Query |
|---|---|---|
| MembershipApplications | `U(application_number)` | lookup |
| MembershipApplications | `(status, submitted_at DESC)` | admin queue default view |
| MembershipApplications | `(current_stage_id, status)` | per-stage approver queue |
| MembershipApplications | `(user_id, "createdAt" DESC)` | member "my applications" |
| MembershipApplications | partial `U(user_id) WHERE status IN (DRAFT,SUBMITTED,UNDER_REVIEW,RETURNED_FOR_CORRECTION)` | one open application |
| ApplicationDocuments | `(application_id, document_type_id)` | review screen |
| ApplicationDocuments | `(verification_status)` | pending-verification queue |
| MemberDocuments | `(member_id, document_type_id)` | member KYC tab |
| ApprovalRequests | `(status, current_stage_id)` | approver queue |
| ApprovalRequests | `(application_id)` / `(profile_change_request_id)` | subject → request |
| ApprovalActions | `(approval_request_id, acted_at DESC)` | history timeline |
| ApprovalActions | `(admin_user_id, acted_at DESC)` | "my actions" audit |
| ApprovalStages | `U(workflow_id, sequence)` | next-stage resolution |

## Billing

| Table | Index | Query |
|---|---|---|
| Invoices | `U(invoice_number)` | lookup |
| Invoices | `(member_id, status, issue_date DESC)` | member invoice list |
| Invoices | `(status, due_date)` | overdue sweep + dues dashboard |
| Invoices | `(invoice_type, issue_date DESC)` | revenue report |
| InvoiceItems | `(invoice_id, sort_order)` | invoice render |
| Payments | `U(payment_number)` | lookup |
| Payments | `(invoice_id, status)` | invoice payment state |
| Payments | `(member_id, paid_at DESC)` | payment history |
| Payments | `(status, "createdAt")` | reconciliation, stuck-payment sweep |
| Payments | `U(provider_payment_id) WHERE provider_payment_id IS NOT NULL` | webhook match |
| PaymentWebhookEvents | `U(provider, event_id)` | idempotency (R-7) |
| PaymentWebhookEvents | `(processed_at) WHERE processed_at IS NULL` | retry sweep |
| Receipts | `U(payment_id)`, `U(receipt_number)` | receipt fetch |
| Refunds | `(payment_id, status)`, `(status, "createdAt")` | refund queue |
| RenewalReminders | `U(membership_term_id, reminder_code)` | no duplicate reminder |
| RenewalReminders | `(scheduled_for) WHERE sent_at IS NULL` | daily reminder job |

## Events, communication, audit

| Table | Index | Query |
|---|---|---|
| Events | `U(slug) WHERE "deletedAt" IS NULL` | public event page |
| Events | `(status, is_public, start_at)` | public + admin listings |
| Events | `(start_at DESC)` | upcoming/past split |
| EventRegistrations | partial `U(event_id, member_id)` | duplicate guard |
| EventRegistrations | `(event_id, status)` | attendee list + capacity count |
| EventRegistrations | `(user_id, registered_at DESC)` | "my events" |
| EventAttendance | `U(registration_id)` | check-in |
| Notices | `(status, publish_at DESC)` | publish job + admin list |
| NoticeRecipients | `U(notice_id, member_id)`, `(member_id, read_at)` | member inbox + unread badge |
| NotificationTemplates | `U(code, channel, locale)` | template resolution |
| Notifications | `(status, next_attempt_at)` | outbox drain (hot path) |
| Notifications | `(user_id, channel, read_at)` | in-app bell |
| AuditLogs | `(entity_name, entity_id, "createdAt" DESC)` | entity history panel |
| AuditLogs | `(actor_type, actor_id, "createdAt" DESC)` | actor audit |
| AuditLogs | `("createdAt" DESC)` | global audit feed |
| JobRuns | `(job_name, started_at DESC)` | job health |

## Maintenance notes

- Partial unique indexes are mandatory wherever soft delete applies — a plain unique would block re-registering a deleted email.
- The `Members` GIN index requires `pg_trgm`/tsvector; add the extension in the same migration that creates the index.
- Re-verify the plan for every list endpoint with `EXPLAIN ANALYZE` on seeded data (≥5k members, ≥20k invoices) as part of each module's self-test.
