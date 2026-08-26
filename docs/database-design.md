# Database Design

PostgreSQL + Prisma. Naming per ADR-003: table `PascalCasePlural`, column `snake_case`, timestamps `createdAt` / `updatedAt` / `deletedAt`. Every table has `id BIGSERIAL PRIMARY KEY` unless stated. Money = `Decimal(14,2)`. All FKs have explicit `ON DELETE` / `ON UPDATE`.

Legend: `PK` primary key · `FK→` foreign key · `U` unique · `CK` check constraint · `SD` soft-delete enabled.

---

## A. Identity & Access (M0/M1)

### Users — member/applicant login accounts (SD)
| Column | Type | Notes |
|---|---|---|
| id | bigserial | PK |
| email | citext | U, not null |
| phone | varchar(20) | nullable, U where not null |
| password_hash | text | not null, bcrypt cost 12 |
| full_name | varchar(150) | not null |
| status | enum UserStatus | `PENDING_VERIFICATION\|ACTIVE\|INACTIVE\|BLOCKED`, default PENDING_VERIFICATION |
| email_verified_at | timestamptz | nullable |
| last_login_at | timestamptz | nullable |
| failed_login_count | int | default 0 |
| locked_until | timestamptz | nullable |
| createdAt / updatedAt / deletedAt | timestamptz | |

### AdminUsers — staff accounts (SD)
Same shape as `Users` minus `phone` uniqueness, plus `is_super_admin boolean default false`, `created_by_admin_id FK→AdminUsers.id ON DELETE SET NULL`.

### Roles
`id`, `code varchar(50) U` (`SUPER_ADMIN`,`ADMIN`,`APPROVER`,`ACCOUNTS`), `name`, `description`, `is_system boolean default false` (system roles cannot be deleted), timestamps.

### Permissions
`id`, `module varchar(50)`, `action varchar(50)`, `code varchar(100) U` (= `module.action`, e.g. `application.approve`), `description`. `U(module, action)`.

### RolePermissions
`role_id FK→Roles ON DELETE CASCADE`, `permission_id FK→Permissions ON DELETE CASCADE`, `U(role_id, permission_id)`.

### AdminUserRoles
`admin_user_id FK→AdminUsers ON DELETE CASCADE`, `role_id FK→Roles ON DELETE RESTRICT`, `assigned_by_admin_id FK→AdminUsers ON DELETE SET NULL`, `U(admin_user_id, role_id)`.

### AuthTokens — refresh/session rows for both audiences
`id`, `user_id FK→Users ON DELETE CASCADE` (nullable), `admin_user_id FK→AdminUsers ON DELETE CASCADE` (nullable), `token_hash text U`, `audience enum(MEMBER,ADMIN)`, `expires_at`, `revoked_at`, `ip inet`, `user_agent text`.
`CK: (user_id IS NOT NULL) <> (admin_user_id IS NOT NULL)`.

### OtpCodes
`id`, `identifier varchar(150)` (email/phone), `purpose enum(SIGNUP_VERIFY, PASSWORD_RESET, LOGIN_2FA)`, `code_hash text`, `expires_at`, `consumed_at`, `attempt_count int default 0`. Index `(identifier, purpose, expires_at)`.

### PasswordResetTokens
`id`, `user_id` / `admin_user_id` (same XOR CK as AuthTokens), `token_hash U`, `expires_at`, `used_at`.

---

## B. Membership core (M2 masters, M3 member record)

### MembershipCategories (SD)
`id`, `code varchar(30) U`, `name`, `description`, `is_active bool default true`, `display_order int`, timestamps.

### MembershipTiers (SD)
`id`, `category_id FK→MembershipCategories ON DELETE RESTRICT`, `code varchar(30)`, `name`, `description`, `display_order`, `is_active`. `U(category_id, code)`.

### FeeStructures
`id`, `category_id FK→MembershipCategories ON DELETE RESTRICT`, `tier_id FK→MembershipTiers ON DELETE RESTRICT` (nullable = applies to whole category), `fee_type enum(NEW_MEMBERSHIP, RENEWAL, EVENT_DEFAULT)`, `amount Decimal(14,2)`, `tax_rate Decimal(5,2) default 0`, `currency char(3) default 'INR'`, `duration_months int default 12`, `effective_from date not null`, `effective_to date` nullable, `is_active bool`.
`CK amount >= 0`, `CK effective_to IS NULL OR effective_to > effective_from`. Partial unique: one active row per `(category_id, tier_id, fee_type)` over overlapping dates — enforced by an exclusion constraint on a daterange.

### Members — the organisation record (SD)
| Column | Type | Notes |
|---|---|---|
| id | bigserial | PK |
| member_code | varchar(30) | U, nullable until approved |
| primary_user_id | bigint | FK→Users ON DELETE RESTRICT, U |
| category_id | bigint | FK→MembershipCategories ON DELETE RESTRICT |
| tier_id | bigint | FK→MembershipTiers ON DELETE RESTRICT, nullable |
| company_name | varchar(200) | not null |
| legal_name | varchar(200) | nullable |
| business_type | varchar(100) | nullable (grower/manufacturer/trader…) |
| iec_code | varchar(20) | nullable, U where not null |
| gst_number | varchar(20) | nullable, U where not null, CK format |
| pan_number | varchar(15) | nullable |
| trade_license_no | varchar(50) | nullable |
| website | varchar(200) | nullable |
| about | text | nullable |
| logo_path | text | nullable |
| status | enum MemberStatus | `DRAFT\|PENDING\|ACTIVE\|SUSPENDED\|EXPIRED\|TERMINATED`. `DRAFT` = created when the application starts (ADR-016); `PENDING` = approved, awaiting payment; `ACTIVE` = paid |
| directory_visible | boolean | default true |
| joined_on | date | nullable |
| current_term_id | bigint | FK→MembershipTerms ON DELETE SET NULL, nullable |
| createdAt/updatedAt/deletedAt | timestamptz | |

### MemberContacts
`member_id FK→Members ON DELETE CASCADE`, `name`, `designation`, `email`, `phone`, `is_primary bool`. Partial unique index: one `is_primary = true` per member.

### MemberAddresses
`member_id FK→Members ON DELETE CASCADE`, `address_type enum(REGISTERED, FACTORY, CORRESPONDENCE)`, `line1`, `line2`, `city`, `state`, `country default 'India'`, `pincode varchar(10)`, `is_primary bool`.

### MembershipTerms — one row per membership period (new + each renewal)
`id`, `member_id FK→Members ON DELETE CASCADE`, `category_id`, `tier_id`, `term_type enum(NEW, RENEWAL)`, `valid_from date`, `valid_till date`, `invoice_id FK→Invoices ON DELETE SET NULL` nullable, `status enum(PENDING_PAYMENT, ACTIVE, EXPIRED, CANCELLED)`, timestamps.
`CK valid_till > valid_from`. Index `(member_id, valid_till)`, `(status, valid_till)`.

### MemberStatusHistory
`member_id FK→Members ON DELETE CASCADE`, `from_status`, `to_status`, `reason text`, `changed_by_admin_id FK→AdminUsers ON DELETE SET NULL`, `changed_at timestamptz default now()`.

---

## C. Applications & Approvals (M4)

### MembershipApplications (SD)
`id`, `application_number varchar(30) U`, `user_id FK→Users ON DELETE RESTRICT`, `member_id FK→Members ON DELETE RESTRICT` (set when the draft member is created — ADR-016), `category_id FK→MembershipCategories ON DELETE RESTRICT`, `tier_id` nullable, applicant company fields mirroring `Members` (company_name, legal_name, business_type, iec_code, gst_number, pan_number, trade_license_no, website, about) held as an **immutable submitted snapshot** — the live profile is on `Members` (ADR-016); the snapshot is what the approver saw and is never edited after submission, `contact_json jsonb` **only** for the free-form "additional info" block (documented JSON use, not relational data), `status enum ApplicationStatus` (`DRAFT|SUBMITTED|UNDER_REVIEW|RETURNED_FOR_CORRECTION|APPROVED|REJECTED|WITHDRAWN`), `current_stage_id FK→ApprovalStages ON DELETE SET NULL`, `submitted_at`, `decided_at`, `resubmission_count int default 0`, timestamps.

### DocumentTypes (master)
`id`, `code varchar(50) U`, `name`, `applies_to enum(APPLICATION, MEMBER, BOTH)`, `is_required bool`, `max_size_mb int default 10`, `allowed_mime text[]`, `is_active`.

### ApplicationDocuments
`application_id FK→MembershipApplications ON DELETE CASCADE`, `document_type_id FK→DocumentTypes ON DELETE RESTRICT`, `file_path text`, `original_name`, `mime_type`, `size_bytes bigint`, `checksum_sha256 char(64)`, `verification_status enum(PENDING, VERIFIED, REJECTED) default PENDING`, `verified_by_admin_id`, `verified_at`, `remarks text`, `version int default 1`. Index `(application_id, document_type_id)`.

### MemberDocuments
Same shape, `member_id FK→Members ON DELETE CASCADE`. (ADR-006: two tables instead of a polymorphic one.)

### ApprovalWorkflows
`id`, `code varchar(50) U`, `name`, `subject_type enum(MEMBERSHIP_APPLICATION, PROFILE_CHANGE_REQUEST)`, `is_active bool`, `version int default 1`.

### ApprovalStages
`id`, `workflow_id FK→ApprovalWorkflows ON DELETE CASCADE`, `sequence int`, `name`, `approver_role_id FK→Roles ON DELETE RESTRICT`, `is_final bool default false`, `allow_return bool default true`, `sla_hours int` nullable. `U(workflow_id, sequence)`.

### ApprovalRequests
`id`, `workflow_id FK→ApprovalWorkflows ON DELETE RESTRICT`, `subject_type enum(...)`, `application_id FK→MembershipApplications ON DELETE CASCADE` nullable, `profile_change_request_id FK→MemberProfileChangeRequests ON DELETE CASCADE` nullable, `current_stage_id FK→ApprovalStages ON DELETE RESTRICT`, `status enum(OPEN, APPROVED, REJECTED, RETURNED, WITHDRAWN)`, `opened_at`, `closed_at`.
`CK` exactly one subject FK is non-null and matches `subject_type` (ADR-006).

### ApprovalActions — immutable history, no updates, no deletes
`id`, `approval_request_id FK→ApprovalRequests ON DELETE CASCADE`, `stage_id FK→ApprovalStages ON DELETE RESTRICT`, `admin_user_id FK→AdminUsers ON DELETE RESTRICT`, `action enum(APPROVE, REJECT, RETURN, REASSIGN, COMMENT)`, `from_status`, `to_status`, `remarks text`, `acted_at timestamptz default now()`.

### MemberProfileChangeRequests
`id`, `member_id FK→Members ON DELETE CASCADE`, `requested_by_user_id FK→Users ON DELETE RESTRICT`, `changes_json jsonb` (field → {old, new}; documented JSON use — a diff, not relational data), `status enum(PENDING, APPROVED, REJECTED)`, `decided_by_admin_id`, `decided_at`, `remarks`.

---

## D. Billing & Payments (M4 issuance, M5 payments, M6 renewal)

### Invoices (SD)
`id`, `invoice_number varchar(30) U`, `member_id FK→Members ON DELETE RESTRICT`, `invoice_type enum(MEMBERSHIP, RENEWAL, EVENT, OTHER)`, `membership_term_id FK→MembershipTerms ON DELETE SET NULL` nullable, `event_registration_id FK→EventRegistrations ON DELETE SET NULL` nullable, `status enum(DRAFT, ISSUED, PARTIALLY_PAID, PAID, OVERDUE, CANCELLED)`, `issue_date date`, `due_date date`, `subtotal Decimal(14,2)`, `tax_amount Decimal(14,2) default 0`, `total_amount Decimal(14,2)`, `amount_paid Decimal(14,2) default 0`, `balance_due Decimal(14,2)`, `currency char(3) default 'INR'`, `notes text`, `pdf_path text`, `created_by_admin_id` nullable, timestamps.
`CK total_amount >= 0`, `CK amount_paid >= 0 AND amount_paid <= total_amount`, `CK balance_due = total_amount - amount_paid`, `CK due_date >= issue_date`.

### InvoiceItems
`invoice_id FK→Invoices ON DELETE CASCADE`, `description varchar(300)`, `quantity Decimal(10,2) default 1`, `unit_price Decimal(14,2)`, `tax_rate Decimal(5,2) default 0`, `tax_amount Decimal(14,2)`, `line_total Decimal(14,2)`, `sort_order int`. `CK quantity > 0`.

### Payments
`id`, `payment_number varchar(30) U`, `invoice_id FK→Invoices ON DELETE RESTRICT`, `member_id FK→Members ON DELETE RESTRICT`, `amount Decimal(14,2)`, `currency char(3)`, `method enum(ONLINE, NEFT, CHEQUE, CASH, UPI, ADJUSTMENT)`, `provider varchar(50)` (`MANUAL`/gateway code), `provider_order_id varchar(100)` nullable U, `provider_payment_id varchar(100)` nullable U, `status enum(INITIATED, PENDING, SUCCESS, FAILED, CANCELLED, REFUNDED, PARTIALLY_REFUNDED)`, `paid_at`, `failure_reason text`, `recorded_by_admin_id` nullable, timestamps. `CK amount > 0`.

### PaymentWebhookEvents
`id`, `provider varchar(50)`, `event_id varchar(150)`, `event_type varchar(80)`, `payload_json jsonb` (raw provider body — documented JSON use), `signature_valid bool`, `processed_at`, `processing_error text`. `U(provider, event_id)` ← idempotency guard (R-7).

### Receipts
`id`, `receipt_number varchar(30) U`, `payment_id FK→Payments ON DELETE RESTRICT U`, `issued_at`, `pdf_path text`.

### Refunds
`id`, `payment_id FK→Payments ON DELETE RESTRICT`, `amount Decimal(14,2)`, `reason text`, `status enum(REQUESTED, PROCESSING, COMPLETED, FAILED, REJECTED)`, `provider_refund_id varchar(100)` nullable U, `requested_by_admin_id`, `approved_by_admin_id`, `processed_at`. `CK amount > 0`.

### RenewalReminders
`id`, `membership_term_id FK→MembershipTerms ON DELETE CASCADE`, `reminder_code varchar(20)` (`T_MINUS_30`…), `scheduled_for date`, `sent_at`, `notification_id FK→Notifications ON DELETE SET NULL`. `U(membership_term_id, reminder_code)` ← no duplicate reminders.

---

## E. Events (M7)

### Events (SD)
`id`, `slug varchar(160) U`, `title varchar(200)`, `description text`, `banner_path`, `start_at timestamptz`, `end_at timestamptz`, `venue_name`, `venue_address`, `city`, `is_paid bool default false`, `fee_amount Decimal(14,2) default 0`, `tax_rate Decimal(5,2) default 0`, `capacity int` nullable, `registration_opens_at`, `registration_closes_at`, `status enum(DRAFT, PUBLISHED, CANCELLED, COMPLETED)`, `is_public bool default true`, `created_by_admin_id`, timestamps.
`CK end_at > start_at`, `CK NOT is_paid OR fee_amount > 0`, `CK capacity IS NULL OR capacity > 0`.

### EventRegistrations
`id`, `event_id FK→Events ON DELETE RESTRICT`, `member_id FK→Members ON DELETE RESTRICT` nullable, `user_id FK→Users ON DELETE RESTRICT`, `registration_code varchar(30) U`, `attendee_count int default 1`, `status enum(PENDING_PAYMENT, CONFIRMED, CANCELLED, WAITLISTED)`, `invoice_id FK→Invoices ON DELETE SET NULL` nullable, `registered_at`, `cancelled_at`. `U(event_id, member_id)` where not deleted.

### EventAttendance
`registration_id FK→EventRegistrations ON DELETE CASCADE U`, `checked_in_at`, `checked_in_by_admin_id`, `notes`.

---

## F. Communication & Notifications (M8)

### Notices (SD)
`id`, `title varchar(200)`, `body text`, `notice_type enum(NOTICE, CIRCULAR)`, `audience_type enum(ALL, CATEGORY, TIER, SELECTED)`, `status enum(DRAFT, SCHEDULED, PUBLISHED, ARCHIVED)`, `publish_at`, `published_at`, `attachment_path`, `created_by_admin_id`, timestamps.

### NoticeAudienceRules
`notice_id FK→Notices ON DELETE CASCADE`, `category_id` nullable, `tier_id` nullable. (Normalised targeting — no CSV id strings.)

### NoticeRecipients
`notice_id FK→Notices ON DELETE CASCADE`, `member_id FK→Members ON DELETE CASCADE`, `read_at`, `U(notice_id, member_id)`.

### NotificationTemplates
`id`, `code varchar(80)`, `channel enum(EMAIL, WHATSAPP, IN_APP)`, `locale varchar(10) default 'en'`, `subject varchar(200)`, `body text` (handlebars-style placeholders), `is_active`. `U(code, channel, locale)`.

### Notifications — outbox (ADR-010)
`id`, `user_id FK→Users ON DELETE CASCADE` nullable, `admin_user_id FK→AdminUsers ON DELETE CASCADE` nullable, `member_id FK→Members ON DELETE CASCADE` nullable, `channel enum(EMAIL, WHATSAPP, IN_APP)`, `template_code varchar(80)`, `payload_json jsonb` (template variables — documented JSON use), `to_address varchar(200)`, `status enum(QUEUED, SENDING, SENT, FAILED, CANCELLED)`, `attempt_count int default 0`, `next_attempt_at`, `sent_at`, `error text`, `read_at` (IN_APP), timestamps.
Index `(status, next_attempt_at)` ← the drain query.

---

## G. Organisation, audit, config (M10)

### Designations
`id`, `code U`, `name`, `rank int`, `is_active`.

### Committees
`id`, `name`, `committee_type enum(EXECUTIVE, SUB_COMMITTEE, CHAPTER)`, `parent_committee_id FK→Committees ON DELETE SET NULL` nullable, `chapter_region varchar(100)` nullable, `is_active`.

### CommitteeMembers
`committee_id FK→Committees ON DELETE CASCADE`, `member_id FK→Members ON DELETE RESTRICT`, `designation_id FK→Designations ON DELETE RESTRICT`, `term_start date`, `term_end date` nullable, `is_active`. `CK term_end IS NULL OR term_end > term_start`.

### AuditLogs — append-only
`id bigserial`, `actor_type enum(MEMBER, ADMIN, SYSTEM)`, `actor_id bigint` nullable (soft ref), `action varchar(80)` (`application.approved`), `entity_name varchar(60)`, `entity_id bigint` (soft ref — ADR-006 exception), `before_json jsonb` nullable, `after_json jsonb` nullable, `ip inet`, `user_agent text`, `createdAt timestamptz default now()`.
No `updatedAt`, no `deletedAt`. Revoke UPDATE/DELETE from the app DB role on this table.

### SystemSettings
`id`, `key varchar(80) U`, `value text`, `value_type enum(STRING, NUMBER, BOOLEAN, JSON)`, `group varchar(50)`, `description`, `is_public bool default false` (safe to expose to frontends).

### JobRuns
`id`, `job_name varchar(80)`, `started_at`, `finished_at`, `status enum(RUNNING, SUCCESS, FAILED)`, `processed_count int`, `error text`. Index `(job_name, started_at DESC)`.

---

## H. Global rules

1. **Soft delete** (`deletedAt`) on: Users, AdminUsers, Members, MembershipApplications, MembershipCategories, MembershipTiers, Invoices, Events, Notices. Every read filters `deletedAt IS NULL`; every unique index on these tables is partial (`WHERE "deletedAt" IS NULL`).
2. **Never** hard-delete a row referenced by financial or approval history (`ON DELETE RESTRICT` chosen deliberately on Invoices/Payments/ApprovalActions FKs).
3. **Transactions required** for: application submit, each approval action, approval→member activation, invoice issue, payment success → invoice update → receipt, refund, renewal term creation, event registration + invoice, bulk notice fan-out.
4. **No** comma-separated id strings, no arrays substituting for relations, no polymorphic FKs (except the documented `AuditLogs` soft reference).
5. `citext` extension for case-insensitive emails; `btree_gist` for the FeeStructures date-range exclusion constraint.

---

## I. Table & column comments (mandatory — ADR-013)

Every table and every column in `public` carries a `COMMENT ON`. No exceptions, including join tables, enums-as-columns, `id` and timestamp columns.

### What a good comment says
- **Table:** what one row represents, in business language, plus lifecycle if non-obvious.
- **Column:** meaning, unit/format, allowed values for status columns, and the rule behind it — not a restatement of the column name.

| Bad | Good |
|---|---|
| `'Member id'` | `'FK to Members.id — the association member this invoice is billed to. RESTRICT: financial records are never orphaned.'` |
| `'Status'` | `'Invoice lifecycle: DRAFT, ISSUED, PARTIALLY_PAID, PAID, OVERDUE, CANCELLED. PAID and CANCELLED are terminal.'` |
| `'Amount'` | `'Invoice grand total incl. tax, INR, 2dp. Server-computed as sum(InvoiceItems.line_total); never accepted from the client.'` |

### Prisma side (source of truth)
```prisma
/// One membership invoice raised against a member. Immutable after issue except payment state.
model Invoice {
  /// Surrogate key.
  id             BigInt   @id @default(autoincrement())
  /// Human-facing number, format INV/YYYY-YY/NNNNN. Generated transactionally; never reused.
  invoice_number String   @unique @db.VarChar(30)
  /// FK to Members.id — who is billed. ON DELETE RESTRICT.
  member_id      BigInt
  /// Grand total incl. tax, INR, 2dp. Server-computed from InvoiceItems.
  total_amount   Decimal  @db.Decimal(14, 2)
  @@map("Invoices")
}
```

### SQL side (what actually lands in Postgres)
Appended to the same `migration.sql`:
```sql
COMMENT ON TABLE  "Invoices"                IS 'One membership/renewal/event invoice raised against a member. Immutable after issue except payment state.';
COMMENT ON COLUMN "Invoices"."id"           IS 'Surrogate key.';
COMMENT ON COLUMN "Invoices"."invoice_number" IS 'Human-facing number, format INV/YYYY-YY/NNNNN. Generated transactionally; never reused.';
COMMENT ON COLUMN "Invoices"."member_id"    IS 'FK to Members.id — member being billed. ON DELETE RESTRICT: financial records are never orphaned.';
COMMENT ON COLUMN "Invoices"."total_amount" IS 'Grand total incl. tax, INR, 2dp. Server-computed from InvoiceItems; never accepted from the client.';
```

### Boilerplate comments for repeated columns (use verbatim)
| Column | Comment |
|---|---|
| `id` | `'Surrogate key.'` |
| `createdAt` | `'Row creation timestamp (UTC).'` |
| `updatedAt` | `'Last modification timestamp (UTC).'` |
| `deletedAt` | `'Soft-delete timestamp (UTC). NULL means active; all reads filter deletedAt IS NULL.'` |
| `is_active` | `'Soft on/off switch used instead of deletion so historic references stay resolvable.'` |

### Coverage check
```sql
-- must return zero rows
SELECT c.relname AS table_name, a.attname AS column_name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname <> '_prisma_migrations'
  AND (col_description(c.oid, a.attnum) IS NULL
       OR obj_description(c.oid, 'pg_class') IS NULL);
```
Wrapped as `npm run db:check-comments` (exit 1 on any row). Runs in husky pre-push and in every module's self-test.
