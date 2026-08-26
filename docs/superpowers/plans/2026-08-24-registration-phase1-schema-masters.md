# Registration Redesign — Phase 1: Schema & Masters Implementation Plan

> **Revised 2026-08-24** to match the updated spec: deferred password (`Users.password_hash` nullable), `PENDING_APPROVAL` status, fixed three KYC document seeds, registration-at-submit (no post-login documents). Prisma schema tasks 1–3 are **done in repo**; migration `20260824120000_m5_registration_flow` added. Task 4 fee-constraint fix: use `fee_type WITH =` (not `fee_type::text`). Task 5 audit field is `entityName`, not `entityType`. **Do not expose Document Types admin CRUD** (spec D-3).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add location and company-type masters, restructure `Members` for multi-select categories, nullable flat fees, and auth columns for the deferred-password registration flow — backend compiling, existing endpoints working.

**Architecture:** Migration `20260824120000_m5_registration_flow` creates `CompanyTypes`, `Countries`, `States`, `Cities`, `MemberCategories`; alters `Members`, `MemberAddresses`, `FeeStructures`, `Users`; seeds three fixed `DocumentTypes`. Masters module gains four CRUD resources like categories. Repair all references to dropped `Members.category_id` / `tier_id` / `business_type` in one pass.

**Tech Stack:** PostgreSQL, Prisma 6 (multi-file schema in `backend/prisma/schema/`), Node 24, Express, TypeScript, Zod, path aliases (`@modules`, `@constant`, `@db`, `@utils`).

**Spec:** `docs/specs/2026-08-24-registration-redesign.md`

## Global Constraints

- **No test framework exists in this repo.** Verification is `npm run typecheck`, `npm run lint`, `npx prisma migrate status`, and real HTTP requests.
- **Never modify an applied migration.** Create new migrations only; `20260824120000_m5_registration_flow` is the M5 migration.
- **Never use `prisma db push`.**
- **Document Types:** seed `GST_CERTIFICATE`, `PAN_DOCUMENT`, `TRADE_LICENCE` only; **remove/hide admin Document Types routes** (spec D-3).
- **`Users`:** `password_hash` nullable; default status `PENDING_APPROVAL` for new registrations.
- Every validation message is an **i18n key**.
- Masters CRUD uses `authorize('category.view')` / `authorize('category.manage')`.
- Do not invent business meaning for `Members.company_category` (OQ-R1).

---

### Task 1: Location masters in the Prisma schema

**Files:**
- Create: `backend/prisma/schema/location.prisma`
- Test: none — verified by `prisma validate` and `prisma migrate dev`

**Interfaces:**
- Consumes: nothing.
- Produces: Prisma models `Country`, `State`, `City` mapped to tables `Countries`, `States`, `Cities`. Relation field names `states`, `cities`, `country`, `state`. These names are used by Task 3 (`MemberAddress` FKs) and Task 8 (repository queries).

- [ ] **Step 1: Create the location schema file**

Create `backend/prisma/schema/location.prisma`:

```prisma
// Geography masters (M5 registration): the country → state → city chain the public
// registration form's cascading selects read.
//
// These are masters rather than free text for one reason that shows up in reporting:
// "Surat", "surat" and "SURAT" are three cities in a text column and one row here.
// The member's address still keeps its own text copy — see MemberAddresses — so a
// renamed master never rewrites an address that has already been printed.

/// A country. Seeded, rarely edited, never deleted once an address references it.
model Country {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// ISO-3166-1 alpha-2, e.g. IN. Unique; this is the stable machine name.
  iso_code String @unique @db.Char(2)

  /// Display name, e.g. India.
  name String @db.VarChar(100)

  /// Sort position. Lower first, so India can sit at the top of an Indian form.
  display_order Int @default(0)

  /// Whether the registration form may offer it.
  is_active Boolean @default(true)

  /// Row creation timestamp (UTC).
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// Last modification timestamp (UTC).
  updatedAt DateTime @updatedAt @db.Timestamptz(6)

  /// Soft-delete timestamp (UTC). NULL means active; all reads filter deletedAt IS NULL.
  deletedAt DateTime? @db.Timestamptz(6)

  /// States belonging to this country.
  states State[]

  /// Addresses pinned to this country.
  addresses MemberAddress[]

  @@index([is_active, display_order])
  @@map("Countries")
}

/// A state or province inside a country.
model State {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// FK to Countries.id. ON DELETE RESTRICT — a state must not outlive its country.
  country_id BigInt

  /// Short code, unique within the country, e.g. GJ.
  code String @db.VarChar(10)

  /// Display name, e.g. Gujarat.
  name String @db.VarChar(100)

  /// Whether the registration form may offer it.
  is_active Boolean @default(true)

  /// Row creation timestamp (UTC).
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// Last modification timestamp (UTC).
  updatedAt DateTime @updatedAt @db.Timestamptz(6)

  /// Soft-delete timestamp (UTC). NULL means active; all reads filter deletedAt IS NULL.
  deletedAt DateTime? @db.Timestamptz(6)

  /// The country this state belongs to.
  country Country @relation(fields: [country_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  /// Cities in this state.
  cities City[]

  /// Addresses pinned to this state.
  addresses MemberAddress[]

  @@unique([country_id, code])
  @@index([country_id, name])
  @@map("States")
}

/// A city or town inside a state.
model City {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// FK to States.id. ON DELETE RESTRICT.
  state_id BigInt

  /// Display name, e.g. Surat.
  name String @db.VarChar(100)

  /// Whether the registration form may offer it.
  is_active Boolean @default(true)

  /// Row creation timestamp (UTC).
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// Last modification timestamp (UTC).
  updatedAt DateTime @updatedAt @db.Timestamptz(6)

  /// Soft-delete timestamp (UTC). NULL means active; all reads filter deletedAt IS NULL.
  deletedAt DateTime? @db.Timestamptz(6)

  /// The state this city belongs to.
  state State @relation(fields: [state_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  /// Addresses pinned to this city.
  addresses MemberAddress[]

  @@unique([state_id, name])
  @@index([state_id, name])
  @@map("Cities")
}
```

- [ ] **Step 2: Verify the schema parses**

Run: `cd backend && npx prisma validate`
Expected: FAIL — `Country.addresses` points at `MemberAddress`, which has no matching back-relation yet. The error names the missing field on `MemberAddress`. This is the expected failure; Task 3 adds it.

- [ ] **Step 3: Do not commit yet**

This file does not stand alone. It is committed at the end of Task 3 together with the `MemberAddress` back-relations that make it valid.

---

### Task 2: `CompanyTypes` master and nullable fee category

**Files:**
- Modify: `backend/prisma/schema/membership.prisma` (append `CompanyType` model; alter `FeeStructure.category_id`)

**Interfaces:**
- Consumes: nothing.
- Produces: Prisma model `CompanyType` → table `CompanyTypes`, with relation field `members`. `FeeStructure.category_id` becomes `BigInt?` and `FeeStructure.category` becomes `MembershipCategory?`.

- [ ] **Step 1: Add the `CompanyType` model**

Append to `backend/prisma/schema/membership.prisma`:

```prisma
/// The legal form of a member firm — Proprietary, Partnership, Private Ltd., Public Ltd.
///
/// A master rather than an enum because the association, not the codebase, owns the
/// list: adding "LLP" must be a row an administrator types, not a migration. It has
/// no bearing on price or approval; it is what the firm is registered as.
model CompanyType {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// Stable machine name, e.g. PRIVATE_LTD. Immutable once created.
  code String @unique @db.VarChar(30)

  /// Display name shown on the registration form, e.g. "Private Ltd.".
  name String @db.VarChar(120)

  /// Sort position on the form. Lower first.
  display_order Int @default(0)

  /// Whether the registration form may offer it. Existing members keep theirs regardless.
  is_active Boolean @default(true)

  /// Row creation timestamp (UTC).
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// Last modification timestamp (UTC).
  updatedAt DateTime @updatedAt @db.Timestamptz(6)

  /// Soft-delete timestamp (UTC). NULL means active; all reads filter deletedAt IS NULL.
  deletedAt DateTime? @db.Timestamptz(6)

  /// Firms registered under this legal form.
  members Member[]

  @@index([is_active, display_order])
  @@map("CompanyTypes")
}
```

- [ ] **Step 2: Make the fee's category optional**

In the same file, inside `model FeeStructure`, replace the `category_id` field and its doc comment:

```prisma
  /// FK to MembershipCategories.id — the category being priced. ON DELETE RESTRICT: historic
  /// pricing must stay resolvable.
  category_id BigInt
```

with:

```prisma
  /// FK to MembershipCategories.id, or NULL for the association-wide price.
  ///
  /// NULL is the normal case: the association charges every member the same fee, so
  /// one global row prices everyone (spec D-4). A non-NULL row is the escape hatch
  /// for the day one class is priced differently, and it wins over the global row.
  /// ON DELETE RESTRICT: historic pricing must stay resolvable.
  category_id BigInt?
```

And replace the relation field:

```prisma
  /// The category this price belongs to.
  category MembershipCategory @relation(fields: [category_id], references: [id], onDelete: Restrict, onUpdate: Cascade)
```

with:

```prisma
  /// The category this price belongs to, when it is category-specific.
  category MembershipCategory? @relation(fields: [category_id], references: [id], onDelete: Restrict, onUpdate: Cascade)
```

- [ ] **Step 3: Verify**

Run: `cd backend && npx prisma validate`
Expected: still FAILs on the `MemberAddress` back-relation from Task 1. No *new* error mentioning `CompanyType` or `FeeStructure`. If one appears, fix it before continuing.

- [ ] **Step 4: Do not commit yet**

Committed at the end of Task 3.

---

### Task 3: Restructure `Members` and add the `MemberCategories` join

**Files:**
- Modify: `backend/prisma/schema/member.prisma`

**Interfaces:**
- Consumes: `CompanyType` (Task 2), `Country` / `State` / `City` (Task 1).
- Produces: model `MemberCategory` → table `MemberCategories`, composite PK `(member_id, category_id)`, relation fields `Member.categories` and `MembershipCategory.member_links`. `Member.category_id`, `Member.tier_id`, `Member.business_type`, `Member.category` and `Member.tier` **cease to exist** — Task 4 depends on this.

- [ ] **Step 1: Add the new `Member` columns**

In `backend/prisma/schema/member.prisma`, inside `model Member`, replace the `business_type` field and its doc comment:

```prisma
  /// What the company does — grower, manufacturer, trader. Free text: the
  /// federation's own vocabulary lives in MembershipCategories, and this is the
  /// member's description of themselves.
  business_type String? @db.VarChar(100)
```

with:

```prisma
  /// FK to CompanyTypes.id — the firm's legal form. NULL only for records created
  /// before the master existed. ON DELETE RESTRICT.
  company_type_id BigInt?

  /// Whether the firm holds a GSTIN. Drives whether `gst_number` is required at
  /// registration; false means the GSTIN field was submitted as N/A.
  gstin_holder Boolean @default(false)

  /// The reference form's "Company Category" Yes/No radio, stored verbatim.
  ///
  /// Nothing reads this column. The association has not defined what the question
  /// means (spec OQ-R1), so it is captured rather than interpreted — inventing a
  /// meaning here would be inventing a business rule.
  company_category Boolean?

  /// Landline, as distinct from the primary user's mobile.
  landline String? @db.VarChar(20)

  /// When the applicant ticked the data-processing consent box at registration.
  /// NULL for records created before consent was collected.
  consent_accepted_at DateTime? @db.Timestamptz(6)

  /// The IP the consent was given from. A consent claim that cannot say when and
  /// from where is not a claim that survives being challenged.
  consent_ip String? @db.VarChar(45)
```

- [ ] **Step 2: Remove the single-category columns**

Still inside `model Member`, delete these four blocks entirely:

```prisma
  /// FK to MembershipCategories.id — what the company is applying for or holds.
  /// NULL while the applicant has not chosen yet. ON DELETE RESTRICT.
  category_id BigInt?

  /// FK to MembershipTiers.id, when the chosen category has tiers. ON DELETE RESTRICT.
  tier_id BigInt?
```

```prisma
  /// The membership class this company holds or is applying for.
  category MembershipCategory? @relation(fields: [category_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  /// The band inside that category, when it has one.
  tier MembershipTier? @relation(fields: [tier_id], references: [id], onDelete: Restrict, onUpdate: Cascade)
```

- [ ] **Step 3: Add the new relations and fix the indexes**

Inside `model Member`, add next to the other relation fields:

```prisma
  /// The firm's legal form.
  company_type CompanyType? @relation(fields: [company_type_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  /// Every category this firm claims — the registration form's "Business Nature"
  /// checkboxes. Many, not one (spec D-6).
  categories MemberCategory[]
```

Then replace the three `@@index` lines at the bottom of `model Member`:

```prisma
  @@index([status, category_id, createdAt(sort: Desc)])
  @@index([category_id, tier_id])
  @@index([directory_visible, status])
```

with:

```prisma
  @@index([status, createdAt(sort: Desc)])
  @@index([company_type_id])
  @@index([directory_visible, status])
```

- [ ] **Step 4: Add the join model**

Append to `backend/prisma/schema/member.prisma`:

```prisma
/// A category a member claims. The many-to-many behind the registration form's
/// "Business Nature" checkboxes.
///
/// It is a join table rather than a column because a Surat firm is routinely both a
/// manufacturer and an exporter, and a single `category_id` forced them to pick the
/// one that mattered least. Nothing here prices anything — the association charges
/// one fee regardless of category (spec D-4).
model MemberCategory {
  /// FK to Members.id. ON DELETE CASCADE — a claim is meaningless without its firm.
  member_id BigInt

  /// FK to MembershipCategories.id. ON DELETE RESTRICT — a category that has
  /// classified a member must stay resolvable, the same rule the masters service
  /// already enforces for delete.
  category_id BigInt

  /// When the claim was recorded.
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// The firm making the claim.
  member Member @relation(fields: [member_id], references: [id], onDelete: Cascade, onUpdate: Cascade)

  /// The category claimed.
  category MembershipCategory @relation(fields: [category_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  @@id([member_id, category_id])
  @@index([category_id])
  @@map("MemberCategories")
}
```

- [ ] **Step 5: Add the address FKs**

Inside `model MemberAddress`, immediately after the existing `pincode` field, add:

```prisma
  /// FK to Countries.id. ON DELETE RESTRICT.
  ///
  /// The text `country`, `state` and `city` columns above are kept alongside these
  /// on purpose. They are the snapshot: a master row renamed next year must not
  /// silently rewrite the address that was printed on last year's invoice.
  country_id BigInt?

  /// FK to States.id. ON DELETE RESTRICT.
  state_id BigInt?

  /// FK to Cities.id. ON DELETE RESTRICT.
  city_id BigInt?
```

And with the other relation fields in `model MemberAddress`:

```prisma
  /// The country master row, when the address was captured from the masters.
  country_ref Country? @relation(fields: [country_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  /// The state master row.
  state_ref State? @relation(fields: [state_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  /// The city master row.
  city_ref City? @relation(fields: [city_id], references: [id], onDelete: Restrict, onUpdate: Cascade)
```

- [ ] **Step 6: Add the back-relation on `MembershipCategory`**

In `backend/prisma/schema/membership.prisma`, inside `model MembershipCategory`, next to `members Member[]`, replace:

```prisma
  /// Companies holding or applying for this category.
  members Member[]
```

with:

```prisma
  /// Members claiming this category on the registration form.
  member_links MemberCategory[]
```

- [ ] **Step 7: Remove the tier back-relation on `MembershipTier`**

In `backend/prisma/schema/membership.prisma`, inside `model MembershipTier`, delete:

```prisma
  /// Companies in this band.
  members Member[]
```

- [ ] **Step 8: Verify the whole schema now parses**

Run: `cd backend && npx prisma validate`
Expected: `The schema at prisma/schema is valid 🚀`

If it complains about a missing back-relation, the named model is missing the array field — add it rather than deleting the relation.

- [ ] **Step 9: Commit the schema**

```bash
git add backend/prisma/schema/location.prisma backend/prisma/schema/membership.prisma backend/prisma/schema/member.prisma
git commit -m "feat(db): add location + company-type masters, multi-select member categories"
```

---

### Task 4: Generate and apply the migration

> **Status (2026-08-24):** Applied. Enum split into two migrations (PostgreSQL requires separate commit for new enum values):
> - `20260824115959_m5_user_status_enum` — `ALTER TYPE UserStatus ADD VALUE PENDING_APPROVAL`
> - `20260824120000_m5_registration_flow` — schema + seeds + default status

**Files:**
- Create: `backend/prisma/migrations/<timestamp>_m5_registration_masters/migration.sql`

**Interfaces:**
- Consumes: the schema from Tasks 1–3.
- Produces: the applied migration, and a regenerated Prisma client whose `Member` type no longer has `category_id`, `tier_id` or `business_type`. Task 5 fixes the compile errors this causes.

- [ ] **Step 1: Generate the migration without applying it**

Run: `cd backend && npx prisma migrate dev --create-only --name m5_registration_masters`
Expected: a new folder under `backend/prisma/migrations/` containing `migration.sql`.

- [ ] **Step 2: Read the generated SQL and check three things**

Open the generated `migration.sql` and confirm:

1. It contains `DROP COLUMN "category_id"`, `DROP COLUMN "tier_id"` and `DROP COLUMN "business_type"` on `"Members"`.
2. It contains `ALTER TABLE "FeeStructures" ALTER COLUMN "category_id" DROP NOT NULL;`
3. It does **not** contain `DROP TABLE "MembershipTiers"`. Tiers stay in the schema, unused (spec D-3). If Prisma dropped it, the Task 3 edit removed too much — go back and restore `model MembershipTier`.

- [ ] **Step 3: Rework the fee overlap constraint**

The existing exclusion constraint `FeeStructures_no_overlapping_active_price` was written when `category_id` was `NOT NULL`. In Postgres an exclusion constraint on a nullable column does **not** treat two NULLs as equal, so two global prices could both be active on the same day and the resolver would pick arbitrarily.

Append to the generated `migration.sql`:

```sql
-- The overlap guard has to survive category_id becoming nullable. Postgres does not
-- treat NULL = NULL as a conflict, so two association-wide prices for the same fee
-- type and the same day would both be accepted and the resolver would pick one at
-- random. COALESCE to a sentinel that no real id can take makes the global rows
-- collide with each other exactly as two category rows would.
ALTER TABLE "FeeStructures"
  DROP CONSTRAINT IF EXISTS "FeeStructures_no_overlapping_active_price";

ALTER TABLE "FeeStructures"
  ADD CONSTRAINT "FeeStructures_no_overlapping_active_price"
  EXCLUDE USING gist (
    (COALESCE("category_id", -1)) WITH =,
    (COALESCE("tier_id", -1))     WITH =,
    ("fee_type"::text)            WITH =,
    daterange("effective_from", "effective_to", '[]') WITH &&
  )
  WHERE ("is_active" AND "deletedAt" IS NULL);
```

- [ ] **Step 4: Add the table and column comments**

This codebase documents the database itself — `npm run db:check-comments` enforces it. Append to `migration.sql`:

```sql
COMMENT ON TABLE  "Countries"        IS 'Country master for the registration form''s cascading location selects.';
COMMENT ON TABLE  "States"           IS 'State master, scoped to a country.';
COMMENT ON TABLE  "Cities"           IS 'City master, scoped to a state.';
COMMENT ON TABLE  "CompanyTypes"     IS 'Legal form of a member firm: Proprietary, Partnership, Private Ltd., Public Ltd.';
COMMENT ON TABLE  "MemberCategories" IS 'Categories a member claims — the registration form''s Business Nature checkboxes. Many per member.';

COMMENT ON COLUMN "Members"."company_type_id"     IS 'FK to CompanyTypes.id — the firm''s legal form.';
COMMENT ON COLUMN "Members"."gstin_holder"        IS 'Whether the firm holds a GSTIN; false means gst_number was submitted as N/A.';
COMMENT ON COLUMN "Members"."company_category"    IS 'Reference form''s Company Category Yes/No, captured verbatim. Meaning undefined (spec OQ-R1); nothing reads it.';
COMMENT ON COLUMN "Members"."landline"            IS 'Landline number, distinct from the primary user''s mobile.';
COMMENT ON COLUMN "Members"."consent_accepted_at" IS 'When the data-processing consent box was ticked at registration.';
COMMENT ON COLUMN "Members"."consent_ip"          IS 'IP the consent was given from.';
COMMENT ON COLUMN "MemberAddresses"."country_id"  IS 'FK to Countries.id. The country text column is kept as the snapshot.';
COMMENT ON COLUMN "MemberAddresses"."state_id"    IS 'FK to States.id. The state text column is kept as the snapshot.';
COMMENT ON COLUMN "MemberAddresses"."city_id"     IS 'FK to Cities.id. The city text column is kept as the snapshot.';
COMMENT ON COLUMN "FeeStructures"."category_id"   IS 'FK to MembershipCategories.id, or NULL for the association-wide price.';
```

- [ ] **Step 5: Apply it**

Run: `cd backend && npx prisma migrate dev`
Expected: `Your database is now in sync with your schema.` followed by `Generated Prisma Client`.

If it reports drift and offers to reset, **stop** — a reset destroys local data. Investigate the drift instead.

- [ ] **Step 6: Confirm the client regenerated**

Run: `cd backend && npx prisma migrate status`
Expected: `Database schema is up to date!`

- [ ] **Step 7: Commit**

```bash
git add backend/prisma/migrations
git commit -m "feat(db): migration for registration masters and multi-select categories"
```

---

### Task 5: Repair every reference to the dropped `Member` columns

> **Status (2026-08-24):** Done — backend typecheck passes. `setMemberCategories` / `listMemberCategories` added; member list SQL, activation, application start, and profile/category update paths updated.

**Files:**
- Modify: `backend/src/modules/member/member.types.ts`
- Modify: `backend/src/modules/member/member.repository.ts`
- Modify: `backend/src/modules/member/member.service.ts`
- Modify: `backend/src/modules/application/application.repository.ts`
- Modify: `backend/src/modules/application/application.service.ts`
- Modify: `backend/src/modules/application/activation.service.ts`
- Modify: `backend/src/modules/application/approval.engine.ts`

**Interfaces:**
- Consumes: the regenerated Prisma client from Task 4.
- Produces: a backend that compiles. `member.repository.ts` exports `setMemberCategories(db, memberId, categoryIds)` and `listMemberCategories(db, memberId)`; Phase 2's signup service calls the first, Phase 3's admin detail screen reads the second.

**Context for the implementer:** `MembershipApplications.category_id` and `tier_id` are **not** dropped — they are the approval snapshot. Only `Members.*` changed. Where activation used to copy the application's category onto `Members.category_id`, it now writes a `MemberCategories` row instead.

- [ ] **Step 1: See the full damage**

Run: `cd backend && npm run typecheck 2>&1 | head -60`
Expected: a list of errors, all of the form `Property 'category_id' does not exist on type ...` or `Object literal may only specify known properties`. Note the file list — that is the work.

- [ ] **Step 2: Add the join-table repository functions**

Append to `backend/src/modules/member/member.repository.ts`:

```typescript
/* -------------------------------------------------------------------------- */
/* Member categories — the registration form's "Business Nature" claims         */
/* -------------------------------------------------------------------------- */

/**
 * Replace a member's category claims wholesale.
 *
 * Delete-then-insert rather than a diff: the set is at most a handful of rows, the
 * caller always knows the complete intended set, and a diff would need a second
 * round trip to learn what is already there. Takes `Db` so it can run inside the
 * caller's transaction — registration writes the member and its categories or
 * neither (ADR-010).
 */
export const setMemberCategories = async (
  db: Db,
  memberId: bigint,
  categoryIds: readonly bigint[],
): Promise<void> => {
  await db.memberCategory.deleteMany({ where: { member_id: memberId } });

  if (categoryIds.length === 0) return;

  await db.memberCategory.createMany({
    data: categoryIds.map((category_id) => ({ member_id: memberId, category_id })),
    skipDuplicates: true,
  });
};

/** The categories a member claims, in the master's own display order. */
export const listMemberCategories = (db: Db, memberId: bigint) =>
  db.memberCategory.findMany({
    where: { member_id: memberId, category: { deletedAt: null } },
    select: {
      category: { select: { id: true, code: true, name: true, display_order: true } },
    },
    orderBy: { category: { display_order: 'asc' } },
  });
```

- [ ] **Step 3: Fix the member list query**

In `backend/src/modules/member/member.repository.ts`, the list SQL selects and filters on `m.category_id`. Replace the selected column with an aggregated array so the admin list can still show categories:

Find the `SELECT` list in the member list query and replace `m.category_id,` with:

```sql
           (SELECT string_agg(c.name, ', ' ORDER BY c.display_order)
              FROM "MemberCategories" mc
              JOIN "MembershipCategories" c ON c.id = mc.category_id
             WHERE mc.member_id = m.id AND c."deletedAt" IS NULL) AS category_names,
```

And replace the category filter clause — `AND (${categoryIds}::bigint[] IS NULL OR m.category_id = ANY(${categoryIds}::bigint[]))` — with:

```sql
      AND (${categoryIds}::bigint[] IS NULL
           OR EXISTS (SELECT 1 FROM "MemberCategories" mc2
                       WHERE mc2.member_id = m.id
                         AND mc2.category_id = ANY(${categoryIds}::bigint[])))
```

Update the row interface: replace `category_id: bigint | null;` with `category_names: string | null;`.

- [ ] **Step 4: Fix the member service**

In `backend/src/modules/member/member.service.ts`:

- Delete the tier-belongs-to-category validation block (the one that throws `masters.tierCategoryMismatch` around lines 166–199) — there is no tier on a member any more.
- In the update path, replace the `category: { connect: ... }` / `tier: { connect: ... }` spreads with a call to `repo.setMemberCategories` inside the existing transaction, driven by a new optional `category_ids` input.
- In `member.types.ts`, replace `category_id` and `tier_id` on the update schema with:

```typescript
  /** The member's full set of category claims. Sending it replaces the set. */
  category_ids: z.array(z.string().regex(/^\d+$/, 'validation.invalidId')).max(20).optional(),
```

- In the member list query schema, keep `category_id` as an array filter — it now filters through the join table, which Step 3 already handles.

- [ ] **Step 5: Fix activation**

In `backend/src/modules/application/activation.service.ts`, the approval path writes the application's category and tier onto the member. Replace the `category_id` / `tier_id` assignments in the `member.update` call with a `setMemberCategories` call in the same transaction:

```typescript
  // The application's category becomes the member's first claim. The applicant may
  // have claimed several at registration; approval does not narrow that set, it only
  // guarantees the approved one is in it.
  if (application.category_id !== null) {
    await memberRepo.setMemberCategories(tx, member.id, [
      ...new Set([
        application.category_id,
        ...(await memberRepo.listMemberCategories(tx, member.id)).map((row) => row.category.id),
      ]),
    ]);
  }
```

Leave `MembershipTerm.category_id` and `tier_id` alone — those are on the term, not the member.

- [ ] **Step 6: Fix the fee resolver for a nullable category**

Still in `activation.service.ts`, the fee lookup passes `tierId: application.tier_id`. The resolver must now prefer the global row. In `masters.service.ts`, find `resolveFee` and change its ordering so a NULL category is a valid match and a specific category outranks it:

```typescript
  // Specific beats general, newest beats oldest. A row with category_id NULL is the
  // association-wide price and matches every applicant; a row naming a category wins
  // over it when one exists (spec D-4).
  orderBy: [
    { category_id: { sort: 'desc', nulls: 'last' } },
    { effective_from: 'desc' },
  ],
```

and widen its `where` so `category_id` matches either the requested category or NULL:

```typescript
  where: {
    deletedAt: null,
    is_active: true,
    fee_type: feeType,
    OR: [{ category_id: categoryId }, { category_id: null }],
    effective_from: { lte: onDate },
    AND: [{ OR: [{ effective_to: null }, { effective_to: { gte: onDate } }] }],
  },
```

- [ ] **Step 7: Typecheck until clean**

Run: `cd backend && npm run typecheck`
Expected: no output, exit 0. Repeat Steps 4–6 for any file still listed.

- [ ] **Step 8: Lint**

Run: `cd backend && npm run lint`
Expected: exit 0.

- [ ] **Step 9: Commit**

```bash
git add backend/src
git commit -m "refactor(member): move member category to a join table, make fee category optional"
```

---

### Task 6: Seed the masters

**Files:**
- Create: `backend/prisma/seed/company-types.ts`
- Create: `backend/prisma/seed/locations.ts`
- Modify: `backend/prisma/seed.ts`

**Interfaces:**
- Consumes: the applied migration.
- Produces: exported `seedCompanyTypes(db)` and `seedLocations(db)`, both idempotent (`upsert` on the natural key), called from the existing `seed.ts` entry point.

**Context:** The existing seed deliberately does **not** seed membership categories or fees — those are the association's own decisions (OQ-2). Company types and geography are different: they are facts about India and about company law, not association policy, so seeding them is not inventing a business requirement.

- [ ] **Step 1: Write the company-type seed**

Create `backend/prisma/seed/company-types.ts`:

```typescript
import type { PrismaClient } from '@prisma/client';

/**
 * The four legal forms the reference registration form offers.
 *
 * These are seeded, unlike membership categories, because they are company law
 * rather than association policy — an association does not get to decide what a
 * Partnership is. Adding LLP later is an admin action, not a migration.
 */
const COMPANY_TYPES = [
  { code: 'PROPRIETARY', name: 'Proprietary', display_order: 1 },
  { code: 'PARTNERSHIP', name: 'Partnership', display_order: 2 },
  { code: 'PRIVATE_LTD', name: 'Private Ltd.', display_order: 3 },
  { code: 'PUBLIC_LTD', name: 'Public Ltd.', display_order: 4 },
] as const;

export const seedCompanyTypes = async (db: PrismaClient): Promise<void> => {
  for (const type of COMPANY_TYPES) {
    await db.companyType.upsert({
      where: { code: type.code },
      update: { name: type.name, display_order: type.display_order },
      create: { ...type },
    });
  }
};
```

- [ ] **Step 2: Write the location seed**

Create `backend/prisma/seed/locations.ts`. India first, then its states, then cities. Gujarat and Maharashtra get full district coverage because that is where the membership is; every other state gets its principal cities (spec OQ-R4).

```typescript
import type { PrismaClient } from '@prisma/client';

/**
 * Geography for the registration form's cascading selects.
 *
 * Idempotent: every write is an upsert on the natural key, so running the seed
 * twice is a no-op rather than a duplicate. Re-running after adding a city to the
 * list below adds only that city.
 *
 * Coverage is deliberate, not lazy (spec OQ-R4): Gujarat and Maharashtra carry the
 * membership and are listed in full; every other state carries its principal cities.
 * A missing city is a data row an administrator adds, not a code change.
 */
const STATES: ReadonlyArray<{ code: string; name: string; cities: readonly string[] }> = [
  {
    code: 'GJ',
    name: 'Gujarat',
    cities: [
      'Ahmedabad', 'Amreli', 'Anand', 'Aravalli', 'Banaskantha', 'Bharuch', 'Bhavnagar',
      'Botad', 'Chhota Udepur', 'Dahod', 'Dang', 'Devbhoomi Dwarka', 'Gandhinagar',
      'Gir Somnath', 'Jamnagar', 'Junagadh', 'Kheda', 'Kutch', 'Mahisagar', 'Mehsana',
      'Morbi', 'Narmada', 'Navsari', 'Panchmahal', 'Patan', 'Porbandar', 'Rajkot',
      'Sabarkantha', 'Surat', 'Surendranagar', 'Tapi', 'Vadodara', 'Valsad',
    ],
  },
  {
    code: 'MH',
    name: 'Maharashtra',
    cities: [
      'Ahmednagar', 'Akola', 'Amravati', 'Aurangabad', 'Beed', 'Bhandara', 'Buldhana',
      'Chandrapur', 'Dhule', 'Gadchiroli', 'Gondia', 'Hingoli', 'Jalgaon', 'Jalna',
      'Kolhapur', 'Latur', 'Mumbai', 'Nagpur', 'Nanded', 'Nandurbar', 'Nashik',
      'Osmanabad', 'Palghar', 'Parbhani', 'Pune', 'Raigad', 'Ratnagiri', 'Sangli',
      'Satara', 'Sindhudurg', 'Solapur', 'Thane', 'Wardha', 'Washim', 'Yavatmal',
    ],
  },
  { code: 'AP', name: 'Andhra Pradesh', cities: ['Visakhapatnam', 'Vijayawada', 'Guntur', 'Tirupati', 'Nellore'] },
  { code: 'AR', name: 'Arunachal Pradesh', cities: ['Itanagar', 'Naharlagun'] },
  { code: 'AS', name: 'Assam', cities: ['Guwahati', 'Silchar', 'Dibrugarh', 'Jorhat'] },
  { code: 'BR', name: 'Bihar', cities: ['Patna', 'Gaya', 'Bhagalpur', 'Muzaffarpur'] },
  { code: 'CG', name: 'Chhattisgarh', cities: ['Raipur', 'Bhilai', 'Bilaspur', 'Korba'] },
  { code: 'DL', name: 'Delhi', cities: ['New Delhi', 'North Delhi', 'South Delhi', 'East Delhi', 'West Delhi'] },
  { code: 'GA', name: 'Goa', cities: ['Panaji', 'Margao', 'Vasco da Gama'] },
  { code: 'HR', name: 'Haryana', cities: ['Gurugram', 'Faridabad', 'Panipat', 'Ambala', 'Hisar'] },
  { code: 'HP', name: 'Himachal Pradesh', cities: ['Shimla', 'Solan', 'Dharamshala', 'Mandi'] },
  { code: 'JH', name: 'Jharkhand', cities: ['Ranchi', 'Jamshedpur', 'Dhanbad', 'Bokaro'] },
  { code: 'JK', name: 'Jammu and Kashmir', cities: ['Srinagar', 'Jammu'] },
  { code: 'KA', name: 'Karnataka', cities: ['Bengaluru', 'Mysuru', 'Hubballi', 'Mangaluru', 'Belagavi'] },
  { code: 'KL', name: 'Kerala', cities: ['Thiruvananthapuram', 'Kochi', 'Kozhikode', 'Thrissur', 'Kollam'] },
  { code: 'LA', name: 'Ladakh', cities: ['Leh', 'Kargil'] },
  { code: 'MP', name: 'Madhya Pradesh', cities: ['Bhopal', 'Indore', 'Jabalpur', 'Gwalior', 'Ujjain'] },
  { code: 'MN', name: 'Manipur', cities: ['Imphal'] },
  { code: 'ML', name: 'Meghalaya', cities: ['Shillong', 'Tura'] },
  { code: 'MZ', name: 'Mizoram', cities: ['Aizawl'] },
  { code: 'NL', name: 'Nagaland', cities: ['Kohima', 'Dimapur'] },
  { code: 'OD', name: 'Odisha', cities: ['Bhubaneswar', 'Cuttack', 'Rourkela', 'Puri'] },
  { code: 'PB', name: 'Punjab', cities: ['Ludhiana', 'Amritsar', 'Jalandhar', 'Patiala', 'Mohali'] },
  { code: 'PY', name: 'Puducherry', cities: ['Puducherry', 'Karaikal'] },
  { code: 'RJ', name: 'Rajasthan', cities: ['Jaipur', 'Jodhpur', 'Udaipur', 'Kota', 'Bikaner', 'Ajmer'] },
  { code: 'SK', name: 'Sikkim', cities: ['Gangtok'] },
  { code: 'TN', name: 'Tamil Nadu', cities: ['Chennai', 'Coimbatore', 'Madurai', 'Tiruchirappalli', 'Salem'] },
  { code: 'TS', name: 'Telangana', cities: ['Hyderabad', 'Warangal', 'Nizamabad', 'Karimnagar'] },
  { code: 'TR', name: 'Tripura', cities: ['Agartala'] },
  { code: 'UP', name: 'Uttar Pradesh', cities: ['Lucknow', 'Kanpur', 'Varanasi', 'Agra', 'Noida', 'Ghaziabad', 'Meerut'] },
  { code: 'UK', name: 'Uttarakhand', cities: ['Dehradun', 'Haridwar', 'Roorkee', 'Haldwani'] },
  { code: 'WB', name: 'West Bengal', cities: ['Kolkata', 'Howrah', 'Durgapur', 'Asansol', 'Siliguri'] },
  { code: 'AN', name: 'Andaman and Nicobar Islands', cities: ['Port Blair'] },
  { code: 'CH', name: 'Chandigarh', cities: ['Chandigarh'] },
  { code: 'DN', name: 'Dadra and Nagar Haveli and Daman and Diu', cities: ['Silvassa', 'Daman', 'Diu'] },
  { code: 'LD', name: 'Lakshadweep', cities: ['Kavaratti'] },
];

export const seedLocations = async (db: PrismaClient): Promise<void> => {
  const india = await db.country.upsert({
    where: { iso_code: 'IN' },
    update: { name: 'India', display_order: 1 },
    create: { iso_code: 'IN', name: 'India', display_order: 1 },
  });

  for (const state of STATES) {
    const row = await db.state.upsert({
      where: { country_id_code: { country_id: india.id, code: state.code } },
      update: { name: state.name },
      create: { country_id: india.id, code: state.code, name: state.name },
    });

    for (const city of state.cities) {
      await db.city.upsert({
        where: { state_id_name: { state_id: row.id, name: city } },
        update: {},
        create: { state_id: row.id, name: city },
      });
    }
  }
};
```

- [ ] **Step 3: Call both from the seed entry point**

In `backend/prisma/seed.ts`, add the imports and call them alongside the existing seeds:

```typescript
import { seedCompanyTypes } from './seed/company-types';
import { seedLocations } from './seed/locations';
```

and inside the main seed function:

```typescript
  // Facts, not association policy — safe to seed. Membership categories and fees
  // stay unseeded on purpose (OQ-2): a wrong default becomes the price list.
  await seedCompanyTypes(prisma);
  await seedLocations(prisma);
```

- [ ] **Step 4: Run the seed**

Run: `cd backend && npm run prisma:seed`
Expected: completes without error.

- [ ] **Step 5: Verify the data landed**

Run:
```bash
cd backend && npx prisma db execute --stdin <<'SQL'
SELECT (SELECT count(*) FROM "Countries")    AS countries,
       (SELECT count(*) FROM "States")       AS states,
       (SELECT count(*) FROM "Cities")       AS cities,
       (SELECT count(*) FROM "CompanyTypes") AS company_types;
SQL
```
Expected: `countries = 1`, `states = 36`, `cities` ≥ 150, `company_types = 4`.

- [ ] **Step 6: Verify it is idempotent**

Run: `cd backend && npm run prisma:seed` a second time, then re-run the count query from Step 5.
Expected: identical counts. If any number grew, an `upsert` is keyed on the wrong column.

- [ ] **Step 7: Commit**

```bash
git add backend/prisma/seed.ts backend/prisma/seed
git commit -m "feat(db): seed company types and Indian geography"
```

---

### Task 7: Request schemas and endpoint constants for the four new masters

**Files:**
- Modify: `backend/src/constant/endPoints.constant.ts`
- Modify: `backend/src/modules/masters/masters.types.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `END_POINTS.COMPANY_TYPES` / `COUNTRIES` / `STATES` / `CITIES`; Zod schemas `createCompanyTypeSchema`, `updateCompanyTypeSchema`, `createCountrySchema`, `updateCountrySchema`, `createStateSchema`, `updateStateSchema`, `stateListQuerySchema`, `createCitySchema`, `updateCitySchema`, `cityListQuerySchema`, and the inferred input types `CreateCompanyTypeInput` etc. Tasks 8–10 consume all of these.

- [ ] **Step 1: Add the endpoint constants**

In `backend/src/constant/endPoints.constant.ts`, after the `MEMBERSHIP` line inside `END_POINTS`:

```typescript
  // M5 — registration masters. Company legal form, and the country → state → city
  // chain the public registration form's cascading selects read.
  COMPANY_TYPES: '/company-types',
  COUNTRIES: '/countries',
  STATES: '/states',
  CITIES: '/cities',
  REGISTRATION_CONSENT: '/registration-consent',
```

- [ ] **Step 2: Add the schemas**

Append to `backend/src/modules/masters/masters.types.ts`. The `code`, `name` and `listQuerySchema` helpers already exist at the top of that file — reuse them rather than redefining.

```typescript
/* -------------------------------------------------------------------------- */
/* M5 — registration masters                                                    */
/* -------------------------------------------------------------------------- */

/** A referenced master row id, as a numeric string. BigInt does not survive JSON. */
const referenceId = z
  .string({ required_error: 'validation.requiredFields' })
  .regex(/^\d+$/, 'validation.invalidId');

export const createCompanyTypeSchema = z.object({
  code,
  name,
  display_order: z.coerce.number().int().min(0).max(9999).optional(),
  is_active: z.boolean().optional(),
});

/** `code` is absent on purpose: a machine name is immutable once anything references it. */
export const updateCompanyTypeSchema = z
  .object({
    name: name.optional(),
    display_order: z.coerce.number().int().min(0).max(9999).optional(),
    is_active: z.boolean().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'validation.requiredFields');

export const createCountrySchema = z.object({
  iso_code: z
    .string({ required_error: 'validation.requiredFields' })
    .trim()
    .length(2, 'masters.invalidCode')
    .regex(/^[A-Z]{2}$/, 'masters.invalidCode'),
  name: z.string({ required_error: 'validation.requiredFields' }).trim().min(1).max(100),
  display_order: z.coerce.number().int().min(0).max(9999).optional(),
  is_active: z.boolean().optional(),
});

export const updateCountrySchema = z
  .object({
    name: z.string().trim().min(1).max(100).optional(),
    display_order: z.coerce.number().int().min(0).max(9999).optional(),
    is_active: z.boolean().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'validation.requiredFields');

export const createStateSchema = z.object({
  country_id: referenceId,
  code: z
    .string({ required_error: 'validation.requiredFields' })
    .trim()
    .min(1)
    .max(10)
    .regex(/^[A-Z0-9]+$/, 'masters.invalidCode'),
  name: z.string({ required_error: 'validation.requiredFields' }).trim().min(1).max(100),
  is_active: z.boolean().optional(),
});

export const updateStateSchema = z
  .object({
    name: z.string().trim().min(1).max(100).optional(),
    is_active: z.boolean().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'validation.requiredFields');

export const stateListQuerySchema = listQuerySchema.extend({
  country_id: referenceId.optional(),
});

export const createCitySchema = z.object({
  state_id: referenceId,
  name: z.string({ required_error: 'validation.requiredFields' }).trim().min(1).max(100),
  is_active: z.boolean().optional(),
});

export const updateCitySchema = z
  .object({
    name: z.string().trim().min(1).max(100).optional(),
    is_active: z.boolean().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'validation.requiredFields');

export const cityListQuerySchema = listQuerySchema.extend({
  state_id: referenceId.optional(),
});

/** Public cascade reads. `state_id` is required — an unscoped city list is 150+ rows
 *  of noise and the form never wants it. */
export const publicStatesQuerySchema = z.object({ country_id: referenceId });
export const publicCitiesQuerySchema = z.object({ state_id: referenceId });

export type CreateCompanyTypeInput = z.infer<typeof createCompanyTypeSchema>;
export type UpdateCompanyTypeInput = z.infer<typeof updateCompanyTypeSchema>;
export type CreateCountryInput = z.infer<typeof createCountrySchema>;
export type UpdateCountryInput = z.infer<typeof updateCountrySchema>;
export type CreateStateInput = z.infer<typeof createStateSchema>;
export type UpdateStateInput = z.infer<typeof updateStateSchema>;
export type CreateCityInput = z.infer<typeof createCitySchema>;
export type UpdateCityInput = z.infer<typeof updateCitySchema>;
```

- [ ] **Step 3: Typecheck**

Run: `cd backend && npm run typecheck`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add backend/src/constant/endPoints.constant.ts backend/src/modules/masters/masters.types.ts
git commit -m "feat(masters): request schemas for company type and location masters"
```

---

### Task 8: Repository layer for the four new masters

**Files:**
- Modify: `backend/src/modules/masters/masters.repository.ts`

**Interfaces:**
- Consumes: the Prisma client from Task 4.
- Produces: `listCompanyTypes(db, params)`, `listCountries(db, params)`, `listStates(db, params)`, `listCities(db, params)`, each returning rows carrying a windowed `total: bigint`; plus `activeCompanyTypes(db)`, `activeCountries(db)`, `activeStates(db, countryId)`, `activeCities(db, stateId)` for the public cascade. Task 9 consumes all eight.

**Context:** Follow the file's existing convention exactly — list reads are raw parameterised SQL with a windowed total and dependency counts; every optional filter is bound as NULL and switched off inside the SQL rather than concatenated. Point reads and writes use the typed client.

- [ ] **Step 1: Add the company-type reads**

Append to `backend/src/modules/masters/masters.repository.ts`:

```typescript
/* -------------------------------------------------------------------------- */
/* Company types                                                                */
/* -------------------------------------------------------------------------- */

export interface CompanyTypeRow {
  id: bigint;
  code: string;
  name: string;
  display_order: number;
  is_active: boolean;
  member_count: bigint;
  createdAt: Date;
  updatedAt: Date;
  total: bigint;
}

export const listCompanyTypes = (
  db: Db,
  params: {
    search?: string | undefined;
    isActive?: boolean | undefined;
    limit: number;
    offset: number;
  },
): Promise<CompanyTypeRow[]> => {
  const search = params.search ? `%${params.search}%` : null;
  const isActive = params.isActive ?? null;

  // member_count is a correlated subquery, not a second round trip: the admin screen
  // needs it to explain why a row cannot be deleted.
  return db.$queryRaw<CompanyTypeRow[]>`
    SELECT ct.id,
           ct.code,
           ct.name,
           ct.display_order,
           ct.is_active,
           (SELECT count(*) FROM "Members" m
              WHERE m.company_type_id = ct.id AND m."deletedAt" IS NULL) AS member_count,
           ct."createdAt",
           ct."updatedAt",
           count(*) OVER () AS total
      FROM "CompanyTypes" ct
     WHERE ct."deletedAt" IS NULL
       AND (${search}::text IS NULL OR ct.name ILIKE ${search}::text OR ct.code ILIKE ${search}::text)
       AND (${isActive}::boolean IS NULL OR ct.is_active = ${isActive}::boolean)
     ORDER BY ct.display_order ASC, ct.name ASC
     LIMIT ${params.limit} OFFSET ${params.offset}`;
};

/** The public form's options: active rows only, in display order, no counts. */
export const activeCompanyTypes = (db: Db) =>
  db.companyType.findMany({
    where: { deletedAt: null, is_active: true },
    select: { id: true, code: true, name: true, display_order: true },
    orderBy: [{ display_order: 'asc' }, { name: 'asc' }],
  });
```

- [ ] **Step 2: Add the location reads**

Append:

```typescript
/* -------------------------------------------------------------------------- */
/* Countries, states, cities                                                    */
/* -------------------------------------------------------------------------- */

export interface CountryRow {
  id: bigint;
  iso_code: string;
  name: string;
  display_order: number;
  is_active: boolean;
  state_count: bigint;
  createdAt: Date;
  updatedAt: Date;
  total: bigint;
}

export const listCountries = (
  db: Db,
  params: {
    search?: string | undefined;
    isActive?: boolean | undefined;
    limit: number;
    offset: number;
  },
): Promise<CountryRow[]> => {
  const search = params.search ? `%${params.search}%` : null;
  const isActive = params.isActive ?? null;

  return db.$queryRaw<CountryRow[]>`
    SELECT c.id,
           c.iso_code,
           c.name,
           c.display_order,
           c.is_active,
           (SELECT count(*) FROM "States" s
              WHERE s.country_id = c.id AND s."deletedAt" IS NULL) AS state_count,
           c."createdAt",
           c."updatedAt",
           count(*) OVER () AS total
      FROM "Countries" c
     WHERE c."deletedAt" IS NULL
       AND (${search}::text IS NULL OR c.name ILIKE ${search}::text OR c.iso_code ILIKE ${search}::text)
       AND (${isActive}::boolean IS NULL OR c.is_active = ${isActive}::boolean)
     ORDER BY c.display_order ASC, c.name ASC
     LIMIT ${params.limit} OFFSET ${params.offset}`;
};

export interface StateRow {
  id: bigint;
  country_id: bigint;
  country_name: string;
  code: string;
  name: string;
  is_active: boolean;
  city_count: bigint;
  createdAt: Date;
  updatedAt: Date;
  total: bigint;
}

export const listStates = (
  db: Db,
  params: {
    search?: string | undefined;
    isActive?: boolean | undefined;
    countryId?: bigint | undefined;
    limit: number;
    offset: number;
  },
): Promise<StateRow[]> => {
  const search = params.search ? `%${params.search}%` : null;
  const isActive = params.isActive ?? null;
  const countryId = params.countryId ?? null;

  // The country name is joined rather than fetched per row — the admin list shows it
  // in every row and an N+1 here is one query per state.
  return db.$queryRaw<StateRow[]>`
    SELECT s.id,
           s.country_id,
           co.name AS country_name,
           s.code,
           s.name,
           s.is_active,
           (SELECT count(*) FROM "Cities" ci
              WHERE ci.state_id = s.id AND ci."deletedAt" IS NULL) AS city_count,
           s."createdAt",
           s."updatedAt",
           count(*) OVER () AS total
      FROM "States" s
      JOIN "Countries" co ON co.id = s.country_id
     WHERE s."deletedAt" IS NULL
       AND (${search}::text IS NULL OR s.name ILIKE ${search}::text OR s.code ILIKE ${search}::text)
       AND (${isActive}::boolean IS NULL OR s.is_active = ${isActive}::boolean)
       AND (${countryId}::bigint IS NULL OR s.country_id = ${countryId}::bigint)
     ORDER BY co.display_order ASC, s.name ASC
     LIMIT ${params.limit} OFFSET ${params.offset}`;
};

export interface CityRow {
  id: bigint;
  state_id: bigint;
  state_name: string;
  country_name: string;
  name: string;
  is_active: boolean;
  address_count: bigint;
  createdAt: Date;
  updatedAt: Date;
  total: bigint;
}

export const listCities = (
  db: Db,
  params: {
    search?: string | undefined;
    isActive?: boolean | undefined;
    stateId?: bigint | undefined;
    limit: number;
    offset: number;
  },
): Promise<CityRow[]> => {
  const search = params.search ? `%${params.search}%` : null;
  const isActive = params.isActive ?? null;
  const stateId = params.stateId ?? null;

  return db.$queryRaw<CityRow[]>`
    SELECT ci.id,
           ci.state_id,
           s.name  AS state_name,
           co.name AS country_name,
           ci.name,
           ci.is_active,
           (SELECT count(*) FROM "MemberAddresses" a
              WHERE a.city_id = ci.id AND a."deletedAt" IS NULL) AS address_count,
           ci."createdAt",
           ci."updatedAt",
           count(*) OVER () AS total
      FROM "Cities" ci
      JOIN "States"    s  ON s.id  = ci.state_id
      JOIN "Countries" co ON co.id = s.country_id
     WHERE ci."deletedAt" IS NULL
       AND (${search}::text IS NULL OR ci.name ILIKE ${search}::text)
       AND (${isActive}::boolean IS NULL OR ci.is_active = ${isActive}::boolean)
       AND (${stateId}::bigint IS NULL OR ci.state_id = ${stateId}::bigint)
     ORDER BY s.name ASC, ci.name ASC
     LIMIT ${params.limit} OFFSET ${params.offset}`;
};

export const activeCountries = (db: Db) =>
  db.country.findMany({
    where: { deletedAt: null, is_active: true },
    select: { id: true, iso_code: true, name: true },
    orderBy: [{ display_order: 'asc' }, { name: 'asc' }],
  });

export const activeStates = (db: Db, countryId: bigint) =>
  db.state.findMany({
    where: { deletedAt: null, is_active: true, country_id: countryId },
    select: { id: true, code: true, name: true },
    orderBy: { name: 'asc' },
  });

export const activeCities = (db: Db, stateId: bigint) =>
  db.city.findMany({
    where: { deletedAt: null, is_active: true, state_id: stateId },
    select: { id: true, name: true },
    orderBy: { name: 'asc' },
  });
```

- [ ] **Step 3: Typecheck**

Run: `cd backend && npm run typecheck`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add backend/src/modules/masters/masters.repository.ts
git commit -m "feat(masters): repository reads for company type and location masters"
```

---

### Task 9: Service layer for the four new masters

**Files:**
- Modify: `backend/src/modules/masters/masters.service.ts`
- Modify: `backend/src/constant/audit.constant.ts`

**Interfaces:**
- Consumes: Task 7's schemas, Task 8's repository functions.
- Produces: for each of company type / country / state / city — `list*`, `get*`, `create*`, `update*`, `delete*`; plus `registrationOptions()` returning `{ company_types, countries }` for the public form. Task 10 consumes all of them.

- [ ] **Step 1: Add the audit action constants**

In `backend/src/constant/audit.constant.ts`, add to `AUDIT_ACTIONS` following the existing naming:

```typescript
  COMPANY_TYPE_CREATED: 'company_type.created',
  COMPANY_TYPE_UPDATED: 'company_type.updated',
  COMPANY_TYPE_DELETED: 'company_type.deleted',
  COUNTRY_CREATED: 'country.created',
  COUNTRY_UPDATED: 'country.updated',
  COUNTRY_DELETED: 'country.deleted',
  STATE_CREATED: 'state.created',
  STATE_UPDATED: 'state.updated',
  STATE_DELETED: 'state.deleted',
  CITY_CREATED: 'city.created',
  CITY_UPDATED: 'city.updated',
  CITY_DELETED: 'city.deleted',
```

- [ ] **Step 2: Add the company-type service**

Append to `backend/src/modules/masters/masters.service.ts`:

```typescript
/* -------------------------------------------------------------------------- */
/* Company types                                                                */
/* -------------------------------------------------------------------------- */

export const listCompanyTypes = async (query: {
  page: number;
  limit: number;
  search?: string | undefined;
  status?: string | undefined;
}) =>
  paged(
    await repo.listCompanyTypes(prisma, {
      search: query.search,
      isActive: selectedActiveState(query.status),
      limit: query.limit,
      offset: (query.page - 1) * query.limit,
    }),
  );

export const getCompanyType = async (id: bigint) => {
  const row = await prisma.companyType.findFirst({ where: { id, deletedAt: null } });

  if (!row) throw notFound('masters.companyTypeNotFound');

  return row;
};

export const createCompanyType = async (input: CreateCompanyTypeInput, actor: Actor) => {
  const existing = await prisma.companyType.findFirst({ where: { code: input.code } });

  // A soft-deleted row still owns the unique code. Reviving it beats refusing the
  // create with a conflict the administrator cannot see the cause of.
  if (existing) {
    if (existing.deletedAt === null) throw conflict('masters.duplicateCode');

    const revived = await prisma.companyType.update({
      where: { id: existing.id },
      data: {
        name: input.name,
        display_order: input.display_order ?? 0,
        is_active: input.is_active ?? true,
        deletedAt: null,
      },
    });

    await writeAudit(prisma, {
      ...audited(actor),
      action: AUDIT_ACTIONS.COMPANY_TYPE_CREATED,
      entityType: 'CompanyType',
      entityId: revived.id,
      after: { code: revived.code, name: revived.name },
    });

    return revived;
  }

  const created = await prisma.companyType.create({
    data: {
      code: input.code,
      name: input.name,
      display_order: input.display_order ?? 0,
      is_active: input.is_active ?? true,
    },
  });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.COMPANY_TYPE_CREATED,
    entityType: 'CompanyType',
    entityId: created.id,
    after: { code: created.code, name: created.name },
  });

  return created;
};

export const updateCompanyType = async (
  id: bigint,
  input: UpdateCompanyTypeInput,
  actor: Actor,
) => {
  const before = await getCompanyType(id);

  const updated = await prisma.companyType.update({ where: { id }, data: { ...input } });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.COMPANY_TYPE_UPDATED,
    entityType: 'CompanyType',
    entityId: id,
    before: { name: before.name, display_order: before.display_order, is_active: before.is_active },
    after: { name: updated.name, display_order: updated.display_order, is_active: updated.is_active },
  });

  return updated;
};

/**
 * Soft delete, refused while a member depends on it.
 *
 * Deactivate-never-delete is the rule for the whole catalogue: a member's legal form
 * must stay resolvable for as long as the member exists, so the escape hatch is
 * `is_active = false`, which hides it from new registrations without erasing history.
 */
export const deleteCompanyType = async (id: bigint, actor: Actor) => {
  const row = await getCompanyType(id);

  const members = await prisma.member.count({
    where: { company_type_id: id, deletedAt: null },
  });

  if (members > 0) throw conflict('masters.companyTypeInUse', { members });

  await prisma.companyType.update({ where: { id }, data: { deletedAt: new Date() } });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.COMPANY_TYPE_DELETED,
    entityType: 'CompanyType',
    entityId: id,
    before: { code: row.code, name: row.name },
  });
};
```

- [ ] **Step 3: Add the country, state and city services**

Append the same five-function shape for each. The dependency check before delete differs per level:

```typescript
/* -------------------------------------------------------------------------- */
/* Countries, states, cities                                                    */
/* -------------------------------------------------------------------------- */

export const listCountries = async (query: {
  page: number;
  limit: number;
  search?: string | undefined;
  status?: string | undefined;
}) =>
  paged(
    await repo.listCountries(prisma, {
      search: query.search,
      isActive: selectedActiveState(query.status),
      limit: query.limit,
      offset: (query.page - 1) * query.limit,
    }),
  );

export const getCountry = async (id: bigint) => {
  const row = await prisma.country.findFirst({ where: { id, deletedAt: null } });

  if (!row) throw notFound('masters.countryNotFound');

  return row;
};

export const createCountry = async (input: CreateCountryInput, actor: Actor) => {
  const existing = await prisma.country.findFirst({ where: { iso_code: input.iso_code } });

  if (existing && existing.deletedAt === null) throw conflict('masters.duplicateCode');

  const row = existing
    ? await prisma.country.update({
        where: { id: existing.id },
        data: {
          name: input.name,
          display_order: input.display_order ?? 0,
          is_active: input.is_active ?? true,
          deletedAt: null,
        },
      })
    : await prisma.country.create({
        data: {
          iso_code: input.iso_code,
          name: input.name,
          display_order: input.display_order ?? 0,
          is_active: input.is_active ?? true,
        },
      });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.COUNTRY_CREATED,
    entityType: 'Country',
    entityId: row.id,
    after: { iso_code: row.iso_code, name: row.name },
  });

  return row;
};

export const updateCountry = async (id: bigint, input: UpdateCountryInput, actor: Actor) => {
  const before = await getCountry(id);
  const updated = await prisma.country.update({ where: { id }, data: { ...input } });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.COUNTRY_UPDATED,
    entityType: 'Country',
    entityId: id,
    before: { name: before.name, is_active: before.is_active },
    after: { name: updated.name, is_active: updated.is_active },
  });

  return updated;
};

export const deleteCountry = async (id: bigint, actor: Actor) => {
  const row = await getCountry(id);

  const states = await prisma.state.count({ where: { country_id: id, deletedAt: null } });

  if (states > 0) throw conflict('masters.countryInUse', { states });

  await prisma.country.update({ where: { id }, data: { deletedAt: new Date() } });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.COUNTRY_DELETED,
    entityType: 'Country',
    entityId: id,
    before: { iso_code: row.iso_code, name: row.name },
  });
};

export const listStates = async (query: {
  page: number;
  limit: number;
  search?: string | undefined;
  status?: string | undefined;
  country_id?: string | undefined;
}) =>
  paged(
    await repo.listStates(prisma, {
      search: query.search,
      isActive: selectedActiveState(query.status),
      countryId: query.country_id ? BigInt(query.country_id) : undefined,
      limit: query.limit,
      offset: (query.page - 1) * query.limit,
    }),
  );

export const getState = async (id: bigint) => {
  const row = await prisma.state.findFirst({ where: { id, deletedAt: null } });

  if (!row) throw notFound('masters.stateNotFound');

  return row;
};

export const createState = async (input: CreateStateInput, actor: Actor) => {
  const countryId = BigInt(input.country_id);

  await getCountry(countryId);

  const existing = await prisma.state.findFirst({
    where: { country_id: countryId, code: input.code },
  });

  if (existing && existing.deletedAt === null) throw conflict('masters.duplicateCode');

  const row = existing
    ? await prisma.state.update({
        where: { id: existing.id },
        data: { name: input.name, is_active: input.is_active ?? true, deletedAt: null },
      })
    : await prisma.state.create({
        data: {
          country_id: countryId,
          code: input.code,
          name: input.name,
          is_active: input.is_active ?? true,
        },
      });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.STATE_CREATED,
    entityType: 'State',
    entityId: row.id,
    after: { code: row.code, name: row.name, country_id: countryId.toString() },
  });

  return row;
};

export const updateState = async (id: bigint, input: UpdateStateInput, actor: Actor) => {
  const before = await getState(id);
  const updated = await prisma.state.update({ where: { id }, data: { ...input } });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.STATE_UPDATED,
    entityType: 'State',
    entityId: id,
    before: { name: before.name, is_active: before.is_active },
    after: { name: updated.name, is_active: updated.is_active },
  });

  return updated;
};

export const deleteState = async (id: bigint, actor: Actor) => {
  const row = await getState(id);

  const cities = await prisma.city.count({ where: { state_id: id, deletedAt: null } });

  if (cities > 0) throw conflict('masters.stateInUse', { cities });

  await prisma.state.update({ where: { id }, data: { deletedAt: new Date() } });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.STATE_DELETED,
    entityType: 'State',
    entityId: id,
    before: { code: row.code, name: row.name },
  });
};

export const listCities = async (query: {
  page: number;
  limit: number;
  search?: string | undefined;
  status?: string | undefined;
  state_id?: string | undefined;
}) =>
  paged(
    await repo.listCities(prisma, {
      search: query.search,
      isActive: selectedActiveState(query.status),
      stateId: query.state_id ? BigInt(query.state_id) : undefined,
      limit: query.limit,
      offset: (query.page - 1) * query.limit,
    }),
  );

export const getCity = async (id: bigint) => {
  const row = await prisma.city.findFirst({ where: { id, deletedAt: null } });

  if (!row) throw notFound('masters.cityNotFound');

  return row;
};

export const createCity = async (input: CreateCityInput, actor: Actor) => {
  const stateId = BigInt(input.state_id);

  await getState(stateId);

  const existing = await prisma.city.findFirst({
    where: { state_id: stateId, name: input.name },
  });

  if (existing && existing.deletedAt === null) throw conflict('masters.duplicateName');

  const row = existing
    ? await prisma.city.update({
        where: { id: existing.id },
        data: { is_active: input.is_active ?? true, deletedAt: null },
      })
    : await prisma.city.create({
        data: { state_id: stateId, name: input.name, is_active: input.is_active ?? true },
      });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.CITY_CREATED,
    entityType: 'City',
    entityId: row.id,
    after: { name: row.name, state_id: stateId.toString() },
  });

  return row;
};

export const updateCity = async (id: bigint, input: UpdateCityInput, actor: Actor) => {
  const before = await getCity(id);
  const updated = await prisma.city.update({ where: { id }, data: { ...input } });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.CITY_UPDATED,
    entityType: 'City',
    entityId: id,
    before: { name: before.name, is_active: before.is_active },
    after: { name: updated.name, is_active: updated.is_active },
  });

  return updated;
};

export const deleteCity = async (id: bigint, actor: Actor) => {
  const row = await getCity(id);

  const addresses = await prisma.memberAddress.count({
    where: { city_id: id, deletedAt: null },
  });

  if (addresses > 0) throw conflict('masters.cityInUse', { addresses });

  await prisma.city.update({ where: { id }, data: { deletedAt: new Date() } });

  await writeAudit(prisma, {
    ...audited(actor),
    action: AUDIT_ACTIONS.CITY_DELETED,
    entityType: 'City',
    entityId: id,
    before: { name: row.name },
  });
};

/**
 * Everything the public registration form needs in one round trip, except the
 * cascade below the country — states and cities are fetched on demand, because
 * shipping every Indian city to a form that will use one is 150 rows of waste.
 */
export const registrationOptions = async () => ({
  company_types: await repo.activeCompanyTypes(prisma),
  countries: await repo.activeCountries(prisma),
});

export const publicStates = async (countryId: bigint) => repo.activeStates(prisma, countryId);

export const publicCities = async (stateId: bigint) => repo.activeCities(prisma, stateId);
```

- [ ] **Step 4: Add the i18n message keys**

Every `messageKey` above must resolve. Add to the English locale under `backend/src/locales/` (find the file holding the existing `masters.*` keys and follow its structure):

```json
  "masters.companyTypeNotFound": "That company type does not exist.",
  "masters.companyTypeInUse": "This company type is used by {{members}} member(s). Deactivate it instead.",
  "masters.countryNotFound": "That country does not exist.",
  "masters.countryInUse": "This country still has {{states}} state(s). Remove them first.",
  "masters.stateNotFound": "That state does not exist.",
  "masters.stateInUse": "This state still has {{cities}} city/cities. Remove them first.",
  "masters.cityNotFound": "That city does not exist.",
  "masters.cityInUse": "This city is used by {{addresses}} address(es). Deactivate it instead.",
  "masters.duplicateName": "A row with that name already exists here."
```

Mirror the same keys into every other locale file present, translated where the file is translated.

- [ ] **Step 5: Typecheck and lint**

Run: `cd backend && npm run typecheck && npm run lint`
Expected: both exit 0.

- [ ] **Step 6: Commit**

```bash
git add backend/src/modules/masters/masters.service.ts backend/src/constant/audit.constant.ts backend/src/locales
git commit -m "feat(masters): service layer for company type and location masters"
```

---

### Task 10: Controllers, routes and the consent setting

**Files:**
- Modify: `backend/src/modules/masters/masters.controller.ts`
- Modify: `backend/src/modules/masters/masters.routes.ts`
- Modify: `backend/prisma/seed.ts` (consent setting row)

**Interfaces:**
- Consumes: Task 9's service functions.
- Produces: the twelve admin routes and five public routes listed in the spec §7. Phase 2's registration form calls `GET /api/v1/public/registration-options`, `/states`, `/cities` and `/registration-consent`.

- [ ] **Step 1: Add the controllers**

Append to `backend/src/modules/masters/masters.controller.ts`, following the existing `handler` / `actor` / `serialise` / `listResponse` helpers already defined at the top of the file:

```typescript
/* --- company types --------------------------------------------------------- */

export const listCompanyTypes = handler(async (req, res) => {
  const query = req.query as unknown as { page: number; limit: number; search?: string; status?: string };

  listResponse(res, await service.listCompanyTypes(query), query);
});

export const getCompanyType = handler(async (req, res) => {
  handleApiResponse(res, {
    responseType: RES_STATUS.GET,
    data: serialise(await service.getCompanyType(BigInt(req.params.id as string))),
  });
});

export const createCompanyType = handler(async (req, res) => {
  handleApiResponse(res, {
    responseType: RES_STATUS.POST,
    data: serialise(await service.createCompanyType(req.body, actor(req))),
  });
});

export const updateCompanyType = handler(async (req, res) => {
  handleApiResponse(res, {
    responseType: RES_STATUS.PUT,
    data: serialise(
      await service.updateCompanyType(BigInt(req.params.id as string), req.body, actor(req)),
    ),
  });
});

export const deleteCompanyType = handler(async (req, res) => {
  await service.deleteCompanyType(BigInt(req.params.id as string), actor(req));

  handleApiResponse(res, { responseType: RES_STATUS.DELETE, data: null });
});
```

Repeat the identical five-handler shape for `Country`, `State` and `City`, substituting the service function names and — for states and cities — widening the list query type to include `country_id` / `state_id`.

Then the public handlers:

```typescript
/* --- public registration reads --------------------------------------------- */

export const registrationOptions = handler(async (_req, res) => {
  handleApiResponse(res, {
    responseType: RES_STATUS.GET,
    data: serialise(await service.registrationOptions()),
  });
});

export const publicStates = handler(async (req, res) => {
  handleApiResponse(res, {
    responseType: RES_STATUS.GET,
    data: serialise(await service.publicStates(BigInt(req.query.country_id as string))),
  });
});

export const publicCities = handler(async (req, res) => {
  handleApiResponse(res, {
    responseType: RES_STATUS.GET,
    data: serialise(await service.publicCities(BigInt(req.query.state_id as string))),
  });
});
```

- [ ] **Step 2: Mount the admin routes**

Append to `backend/src/modules/masters/masters.routes.ts`, before the `mastersPublicRouter` block:

```typescript
/* --- company types --------------------------------------------------------- */

mastersAdminRouter.get(
  END_POINTS.COMPANY_TYPES,
  authorize('category.view'),
  validateRequest({ query: listQuerySchema }),
  controller.listCompanyTypes,
);

mastersAdminRouter.post(
  END_POINTS.COMPANY_TYPES,
  authorize('category.manage'),
  validateRequest({ body: createCompanyTypeSchema }),
  controller.createCompanyType,
);

mastersAdminRouter.get(
  `${END_POINTS.COMPANY_TYPES}/:id`,
  authorize('category.view'),
  validateRequest({ params: idParamSchema }),
  controller.getCompanyType,
);

mastersAdminRouter.patch(
  `${END_POINTS.COMPANY_TYPES}/:id`,
  authorize('category.manage'),
  validateRequest({ params: idParamSchema, body: updateCompanyTypeSchema }),
  controller.updateCompanyType,
);

mastersAdminRouter.delete(
  `${END_POINTS.COMPANY_TYPES}/:id`,
  authorize('category.manage'),
  validateRequest({ params: idParamSchema }),
  controller.deleteCompanyType,
);
```

Repeat for `COUNTRIES` (using `listQuerySchema`, `createCountrySchema`, `updateCountrySchema`), `STATES` (`stateListQuerySchema`, `createStateSchema`, `updateStateSchema`) and `CITIES` (`cityListQuerySchema`, `createCitySchema`, `updateCitySchema`). Add every new schema name to the import block at the top of the file.

- [ ] **Step 3: Mount the public routes**

In the same file, extend the public router:

```typescript
// Unauthenticated on purpose: these feed the public registration form, which by
// definition has no session. They expose only active rows and only id + name —
// nothing an anonymous caller could not read off the form itself.
mastersPublicRouter.get('/registration-options', controller.registrationOptions);

mastersPublicRouter.get(
  END_POINTS.STATES,
  validateRequest({ query: publicStatesQuerySchema }),
  controller.publicStates,
);

mastersPublicRouter.get(
  END_POINTS.CITIES,
  validateRequest({ query: publicCitiesQuerySchema }),
  controller.publicCities,
);
```

- [ ] **Step 4: Seed the consent text setting**

In `backend/prisma/seed.ts`, alongside the other `SystemSetting` seeds, add:

```typescript
  // The consent paragraph is data, not markup, so the association's secretariat can
  // reword it without a deploy. The text below is a neutral placeholder — the real
  // wording is the association's to supply (spec §4.3).
  await prisma.systemSetting.upsert({
    where: { key: 'registration.consent_text' },
    update: {},
    create: {
      key: 'registration.consent_text',
      value:
        'Consent for Collection and Processing of Personal Data: I hereby grant my ' +
        'explicit, informed and voluntary consent to the Association to collect, store, ' +
        'process, share and otherwise use my personal data, including sensitive personal ' +
        'data where applicable, for purposes directly related to the services, activities ' +
        'and statutory obligations of the Association.',
      value_type: 'STRING',
    },
  });
```

- [ ] **Step 5: Re-seed and start the server**

Run: `cd backend && npm run prisma:seed && npm run dev`
Expected: the server starts with no route-registration error.

- [ ] **Step 6: Verify the public endpoints against the running server**

Run:
```bash
curl -s localhost:3000/api/v1/public/registration-options | head -c 400
curl -s 'localhost:3000/api/v1/public/states?country_id=1' | head -c 300
curl -s 'localhost:3000/api/v1/public/cities?state_id=1' | head -c 300
```
Expected: the first returns four company types and one country; the second returns 36 states; the third returns the cities of state 1. Ids are **strings**, not numbers — if they come back as numbers, `serialise` was not applied.

- [ ] **Step 7: Verify an admin route is permission-gated**

Run: `curl -s -o /dev/null -w '%{http_code}\n' localhost:3000/api/v1/admin/company-types`
Expected: `401`. A `200` means `authenticateAdmin` is not applied — check the route was appended to `mastersAdminRouter` and not to the public router.

- [ ] **Step 8: Typecheck, lint, commit**

Run: `cd backend && npm run typecheck && npm run lint`
Expected: both exit 0.

```bash
git add backend/src/modules/masters backend/prisma/seed.ts
git commit -m "feat(masters): admin CRUD and public reads for registration masters"
```

---

## Phase 1 exit criteria

Before starting Phase 2, all of these must hold:

- [ ] `npx prisma migrate status` reports the schema up to date
- [ ] `npm run typecheck` and `npm run lint` pass in `backend/`
- [ ] `npm run prisma:seed` is idempotent — running it twice does not change row counts
- [ ] All five public endpoints return data
- [ ] All twelve admin endpoints return `401` without a token
- [ ] Deleting a company type that a member uses returns `409`, not `500`
- [ ] The existing member list and application queue endpoints still return `200`

## Next

- **Phase 2** — `docs/superpowers/plans/2026-08-24-registration-phase2-signup.md`: captcha service, the expanded signup transaction, and the rebuilt registration form.
- **Phase 3** — `docs/superpowers/plans/2026-08-24-registration-phase3-stepper-admin.md`: stepper reduced to Documents → Review, flat-fee admin screen, four new master screens, member detail fields.
