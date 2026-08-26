# Migration Strategy

## Rules (non-negotiable)

1. Every schema change ships as a Prisma migration: `npx prisma migrate dev --name <scope>_<change>`.
2. **Never** edit a migration that has been applied anywhere beyond the author's laptop. Fix forward with a new migration.
3. **Never** `prisma db push` against dev/staging/production. Local scratch DB only, and never on a DB another agent shares.
4. Deploys run `prisma migrate deploy`. No auto-sync, no `--accept-data-loss`.
5. One migration owner per module cycle (named in the module plan file). The other agent does not touch `prisma/schema/` or `prisma/migrations/` during that cycle (R-3).
6. Any migration containing multiple DDL statements must be reviewed for lock impact; destructive steps are split into their own migration.

## Naming

`YYYYMMDDHHMMSS_<module>_<verb>_<subject>` — e.g. `20260812093000_m3_add_approval_workflow_tables`. Prisma generates the timestamp; the agent supplies `<module>_<verb>_<subject>` via `--name`.

## Baseline handling

`backend/prisma/migrations/20260225095547/` (skeleton `User`/`UserRole`) is already applied. It is **not** edited (ADR-001). M0 adds `20260812xxxxxx_m0_replace_baseline_identity` which drops the placeholder `User` table and creates the real identity model. This is safe only because no production data exists — noted here because it is the single allowed destructive migration in the project.

## Schema file organisation

Prisma multi-file schema under `backend/prisma/schema/`:

```
schema.prisma        # datasource, generator, previewFeatures
identity.prisma      # Users, AdminUsers, Roles, Permissions, tokens
membership.prisma    # Members, categories, tiers, fees, terms
application.prisma   # applications, documents, approvals
billing.prisma       # invoices, payments, receipts, refunds
event.prisma
communication.prisma # notices, templates, notifications
system.prisma        # audit, settings, job runs, designations, committees
```

This lets the two agents work in different files during a cycle even though only one owns the migration for it.

## Per-module migration order (dependency-safe — ADR-019)

| Cycle | Migration content | Depends on |
|---|---|---|
| M0 | extensions (`citext`, `pg_trgm`, `btree_gist`), identity tables, `Roles`/`Permissions`/grants, `AuditLogs`, `SystemSettings`, `JobRuns`, `NotificationTemplates`, `Notifications` (ADR-015) | — |
| M1 | `AuthTokens`, `OtpCodes`, `PasswordResetTokens`; seed roles + permissions + super admin | M0 |
| M2 | `MembershipCategories`, `MembershipTiers`, `FeeStructures` (daterange exclusion), `DocumentTypes` | M0 |
| M3 | `Members` (incl. `DRAFT` status, FKs to categories/tiers), `MemberContacts`, `MemberAddresses`, `MemberDocuments`, `MemberProfileChangeRequests`, `MemberStatusHistory` | M1, M2 |
| M4 | `MembershipApplications`, `ApplicationDocuments`, `ApprovalWorkflows`, `ApprovalStages`, `ApprovalRequests`, `ApprovalActions`, `MembershipTerms`, `Invoices`, `InvoiceItems`, `Members.current_term_id` | M3 |
| M5 | `Payments`, `PaymentWebhookEvents`, `Receipts`, `Refunds` | M4 |
| M6 | `RenewalReminders` (+ any `MembershipTerms` columns renewal needs) | M4, M5 |
| M7 | `Events`, `EventRegistrations`, `EventAttendance` | M4 (invoices for paid events) |
| M8 | `Notices`, `NoticeAudienceRules`, `NoticeRecipients` | M3 |
| M9 | directory GIN index, `Members.directory_visible` (if not already in M3) | M3 |
| M10 | `Designations`, `Committees`, `CommitteeMembers`, report views | M4 |

> The earlier plan created `Members` with nullable category FKs and tightened them later. That deferral is gone: masters (M2) now precede members (M3), so FKs are correct on first creation. Membership terms and invoices are created in M4 because the final-approval transaction must write them atomically (ADR-019).

## Seeds

`prisma/seed.ts` is idempotent (upsert by natural key) and split per module: `seed/roles.ts`, `seed/permissions.ts`, `seed/documentTypes.ts`, `seed/approvalWorkflow.ts`, `seed/notificationTemplates.ts`, `seed/systemSettings.ts`, `seed/superAdmin.ts` (credentials from env, never hardcoded). Business seeds that depend on open questions (categories, tiers, fees) live in `seed/categories.ts` and stay empty until OQ-2 is answered.

## Rollback

Prisma has no down-migrations. Policy: forward-fix. Before any staging/production migration — `pg_dump` snapshot, record it in the release note, verify `prisma migrate status` is clean afterwards. Destructive changes (drop column/table, type narrowing) require: an explicit user approval line in the module plan file, a two-step deploy (stop writing → migrate), and a backup taken in the same hour.

## Verification checklist per migration

- `npx prisma migrate dev` runs clean on an empty DB **and** on a DB with seed data.
- `npx prisma migrate status` reports no drift.
- Every new FK has intentional `onDelete`/`onUpdate` matching `database-relationships.md`.
- Every new unique on a soft-deleted table is partial.
- Every index in `database-indexes.md` for that module exists.
- **`npm run db:check-comments` returns zero rows** — every new table and every new column has a `COMMENT ON` (ADR-013).
- `EXPLAIN ANALYZE` run on the module's list endpoints.

## Comment step in the migration workflow (ADR-013)

Prisma does not emit `COMMENT ON`. Every migration therefore has a mandatory second half:

```bash
npx prisma migrate dev --create-only --name m3_add_approval_tables   # generate SQL, do not apply
# append COMMENT ON TABLE / COMMENT ON COLUMN for every table + column touched
npx prisma migrate dev                                               # apply
npm run db:check-comments                                            # gate, exits 1 on any gap
```

Rules:
- Comments live in the **same** migration file that creates the object — never in a follow-up "add comments" migration.
- `ALTER TABLE … ADD COLUMN` requires its `COMMENT ON COLUMN` in the same file.
- Changing a column's meaning requires a new `COMMENT ON COLUMN` in the migration that changes it.
- Wording rules, boilerplate for repeated columns (`id`, `createdAt`, `deletedAt`, …) and the coverage query: `database-design.md` §I.
- The Prisma `///` doc-comment and the SQL comment must say the same thing; the `///` version is the source the agent copies from.
