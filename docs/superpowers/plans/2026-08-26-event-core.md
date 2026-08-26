# Event Core Implementation Plan (Plan 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An admin can create, price, publish and cancel an event, and members and the public can browse and open it at the right price — everything up to, but not including, pressing Register.

**Architecture:** Events get a fresh `event.prisma` schema file (none exists today — nothing in M0–M5 created these tables, so there is no legacy to migrate). Price is not a column: `EventPriceTiers` holds one row per date window with a member and a non-member price, and a Postgres exclusion constraint makes overlapping windows impossible. Visibility is a single `smallint` that both the public listing and the member listing filter on, so a members-only event is *absent* from public queries rather than fetched and then hidden.

**Tech Stack:** Node.js + Express + TypeScript, Prisma, PostgreSQL, Vitest, React + Ant Design (admin), Next.js (customer).

**Spec:** `docs/superpowers/specs/2026-08-26-event-module-design.md` (sections 1, 3, 8, 9) and `docs/superpowers/specs/2026-08-26-event-module-schema.md` (sections 0, 2).

**Depends on:** Plan 1 (`docs/superpowers/plans/2026-08-26-company-team-logins.md`) — only for Task 8's attendee picker preview; Tasks 1–7 are independent of it.

**Migration owner:** Agent B. Agent A does not touch `prisma/` during this cycle.

## Global Constraints

Identical to Plan 1; copied verbatim from spec section 0 so this plan stands alone.

- **Integer enums.** `Int @db.SmallInt` with a documented code map. Never a Prisma `enum`, never a Postgres native enum. Codes start at 0, append-only, never reused.
- **`bigint` primary keys.** No `uuid` columns. Public links use `Events.slug`.
- **FK actions:** `CASCADE` for owned children, `SET NULL` for pointers, `NO ACTION` everywhere else.
- **Every migration wrapped in `BEGIN;` … `COMMIT;`.** Anything that cannot run in a transaction goes in its own migration.
- **`COMMENT ON` for every new table and column.** `npm run db:check-comments` returns zero rows.
- **Audit block on every new table:** `createdAt`, `created_by_user_id`, `created_by_admin_id`, `updatedAt`, `updated_by_user_id`, `updated_by_admin_id`, plus `deletedAt` where soft-deleted. Both actor columns null means the system did it. Enforced by a `CHECK` that at most one is set.
- **Money** is `Decimal(14,2)`. **Currency** INR only (A-3).
- **Naming (ADR-003):** table `PascalCasePlural`, column `snake_case`, audit timestamps camelCase. Raw SQL double-quotes identifiers.
- **Admin UI:** before touching any admin screen, invoke the `association-admin-ui` skill. No direct `antd` imports for Table/Select/Button/Modal/Pagination; no page sets a colour, radius, height or font-size.

## Scope boundary — read before starting

This plan stops at browsing. Registration, attendees, invoicing, approval and payment verification are **Plan 3**, and Plan 3 is blocked on two findings from the current codebase that need your decision:

1. **`Invoice.member_id` is `NOT NULL`** (`prisma/schema/application.prisma:642`). A non-member guest has no `Members` row, so a guest cannot be invoiced without making that column nullable and adding a `guest_registrant_id` beside it — the nullable-FK + `CHECK` pattern `ApprovalRequests` already uses. That is a change to an M4 table.
2. **There is no `Payments` table.** M5 shipped `Invoice` and `Receipt` and an `applyInvoicePayment` path, but `Payments`/`Refunds` from `database-design.md` were never created. The spec's `PaymentSubmissions.payment_id FK→Payments` therefore has nothing to point at. Recommended: `PaymentSubmissions` verification calls the existing `applyInvoicePayment`, which writes a `Receipt`, and the `payment_id` column is dropped until M5 lands properly.

Neither blocks Tasks 1–9 below.

---

### Task 1: `Events` and `EventPriceTiers`

**Files:**
- Create: `backend/prisma/schema/event.prisma`
- Create: `backend/prisma/migrations/<timestamp>_m7_add_events_and_price_tiers/migration.sql`

**Interfaces:**
- Consumes: `Member`, `AdminUser`, `User` models (existing).
- Produces: Prisma models `Event` (mapped `Events`) and `EventPriceTier` (mapped `EventPriceTiers`).

- [ ] **Step 1: Create the schema file**

Create `backend/prisma/schema/event.prisma`:

```prisma
/// An association event: meeting, seminar, expo. Created as a draft, published
/// to an audience, and priced through EventPriceTiers rather than a fee column —
/// the price depends on when you book and on whether you are a member.
model Event {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// URL-safe identifier used in public links, so a link never exposes a row id.
  slug String @unique @db.VarChar(160)

  /// Shown everywhere the event is listed.
  title String @db.VarChar(200)

  /// Long description, rendered on the detail page.
  description String? @db.Text

  /// Storage key of the banner image, through @helpers/storage.
  banner_path String? @db.Text

  /// Event start (UTC).
  start_at DateTime @db.Timestamptz(6)

  /// Event end (UTC). CHECK end_at > start_at.
  end_at DateTime @db.Timestamptz(6)

  /// Venue name as it appears on the invitation.
  venue_name String? @db.VarChar(200)

  /// Street address, line 1.
  venue_address_line1 String? @db.VarChar(200)

  /// Street address, line 2.
  venue_address_line2 String? @db.VarChar(200)

  /// City. Kept as free text rather than an FK to Cities: a venue may sit outside
  /// the master list, and this is a printed address, not a searchable dimension.
  city String? @db.VarChar(100)

  /// State.
  state String? @db.VarChar(100)

  /// Postal code.
  pincode String? @db.VarChar(10)

  /// Country.
  country String @default("India") @db.VarChar(100)

  /// Optional map link shown on the detail page.
  map_url String? @db.Text

  /// 0 = MEMBER_ONLY (absent from every public query), 1 = PUBLIC.
  visibility Int @default(0) @db.SmallInt

  /// 0 = DRAFT, 1 = PUBLISHED, 2 = CANCELLED, 3 = COMPLETED.
  status Int @default(0) @db.SmallInt

  /// GST or other tax applied on top of the tier price, percent, 2dp.
  tax_rate Decimal @default(0) @db.Decimal(5, 2)

  /// Total seats. NULL means unlimited.
  capacity Int?

  /// Seats consumed by live registrations. Maintained by a single guarded UPDATE
  /// inside the registration transaction (spec section 7) — never read-then-write.
  seats_taken Int @default(0)

  /// When registration opens. NULL means "as soon as it is published".
  registration_opens_at DateTime? @db.Timestamptz(6)

  /// When registration closes. CHECK registration_closes_at <= start_at.
  registration_closes_at DateTime? @db.Timestamptz(6)

  /// When true, a registration waits for admin approval before an invoice exists.
  requires_approval Boolean @default(false)

  /// Collect Veg/Non-veg/Jain per delegate.
  collect_food_preference Boolean @default(true)

  /// Collect a badge photo per delegate.
  collect_photo Boolean @default(false)

  /// Collect a government ID per delegate.
  collect_gov_id Boolean @default(false)

  /// Version of the terms shown at booking, stored on each registration so an old
  /// booking still proves which policy the payer accepted.
  terms_version String @default("v1") @db.VarChar(20)

  /// Row creation timestamp (UTC).
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// Member login that created this row. Always NULL today; events are admin-made.
  created_by_user_id BigInt?

  /// Staff account that created this row.
  created_by_admin_id BigInt?

  /// Last modification timestamp (UTC).
  updatedAt DateTime @updatedAt @db.Timestamptz(6)

  /// Member login that last changed this row.
  updated_by_user_id BigInt?

  /// Staff account that last changed this row.
  updated_by_admin_id BigInt?

  /// Soft-delete timestamp (UTC).
  deletedAt DateTime? @db.Timestamptz(6)

  /// The price windows for this event.
  price_tiers EventPriceTier[]

  @@index([status, visibility, start_at])
  @@map("Events")
}

/// One price window for one event. Two prices per row — member and non-member —
/// and an exclusion constraint guarantees the windows never overlap, so
/// "which price applies today" always has exactly one answer.
model EventPriceTier {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// FK to Events.id. ON DELETE CASCADE — a tier is meaningless without its event.
  event_id BigInt

  /// Label shown to the buyer: "Early bird", "Regular", "Late".
  name String @db.VarChar(60)

  /// First day this price applies, inclusive.
  starts_on DateTime @db.Date

  /// Last day this price applies, inclusive — a tier runs to the end of its last day.
  ends_on DateTime @db.Date

  /// Price per delegate for an active member, INR, 2dp. 0 for a free event.
  member_price Decimal @db.Decimal(14, 2)

  /// Price per delegate for everyone else, INR, 2dp.
  non_member_price Decimal @db.Decimal(14, 2)

  /// Ordering on the admin form and the public price table.
  display_order Int @default(0)

  /// Row creation timestamp (UTC).
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// Member login that created this row. Always NULL today.
  created_by_user_id BigInt?

  /// Staff account that created this row.
  created_by_admin_id BigInt?

  /// Last modification timestamp (UTC).
  updatedAt DateTime @updatedAt @db.Timestamptz(6)

  /// Member login that last changed this row.
  updated_by_user_id BigInt?

  /// Staff account that last changed this row.
  updated_by_admin_id BigInt?

  /// The event priced.
  event Event @relation(fields: [event_id], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@index([event_id, starts_on])
  @@map("EventPriceTiers")
}
```

- [ ] **Step 2: Generate the migration without applying it**

Run:
```bash
cd backend && npx prisma migrate dev --create-only --name m7_add_events_and_price_tiers
```
Expected: a folder with `migration.sql`. Do not apply yet.

- [ ] **Step 3: Wrap it and add the constraints Prisma cannot express**

Put `BEGIN;` at the top, `COMMIT;` at the bottom, and insert this before the `COMMIT;`:

```sql
-- Dates and counts must make sense on their own, independent of application code.
ALTER TABLE "Events" ADD CONSTRAINT "Events_end_after_start"
  CHECK ("end_at" > "start_at");
ALTER TABLE "Events" ADD CONSTRAINT "Events_registration_closes_before_start"
  CHECK ("registration_closes_at" IS NULL OR "registration_closes_at" <= "start_at");
ALTER TABLE "Events" ADD CONSTRAINT "Events_registration_window_ordered"
  CHECK ("registration_opens_at" IS NULL OR "registration_closes_at" IS NULL
         OR "registration_closes_at" >= "registration_opens_at");
ALTER TABLE "Events" ADD CONSTRAINT "Events_capacity_positive"
  CHECK ("capacity" IS NULL OR "capacity" > 0);
ALTER TABLE "Events" ADD CONSTRAINT "Events_seats_taken_non_negative"
  CHECK ("seats_taken" >= 0);

-- The backstop behind the guarded UPDATE in the registration transaction. If any
-- other code path ever writes seats_taken, overselling fails here instead of
-- silently succeeding.
ALTER TABLE "Events" ADD CONSTRAINT "Events_seats_within_capacity"
  CHECK ("capacity" IS NULL OR "seats_taken" <= "capacity");

ALTER TABLE "Events" ADD CONSTRAINT "Events_visibility_range"
  CHECK ("visibility" IN (0, 1));
ALTER TABLE "Events" ADD CONSTRAINT "Events_status_range"
  CHECK ("status" IN (0, 1, 2, 3));
ALTER TABLE "Events" ADD CONSTRAINT "Events_created_by_one_actor"
  CHECK (NOT ("created_by_user_id" IS NOT NULL AND "created_by_admin_id" IS NOT NULL));
ALTER TABLE "Events" ADD CONSTRAINT "Events_updated_by_one_actor"
  CHECK (NOT ("updated_by_user_id" IS NOT NULL AND "updated_by_admin_id" IS NOT NULL));

ALTER TABLE "EventPriceTiers" ADD CONSTRAINT "EventPriceTiers_dates_ordered"
  CHECK ("ends_on" >= "starts_on");
ALTER TABLE "EventPriceTiers" ADD CONSTRAINT "EventPriceTiers_member_price_non_negative"
  CHECK ("member_price" >= 0);
ALTER TABLE "EventPriceTiers" ADD CONSTRAINT "EventPriceTiers_non_member_price_non_negative"
  CHECK ("non_member_price" >= 0);
ALTER TABLE "EventPriceTiers" ADD CONSTRAINT "EventPriceTiers_created_by_one_actor"
  CHECK (NOT ("created_by_user_id" IS NOT NULL AND "created_by_admin_id" IS NOT NULL));
ALTER TABLE "EventPriceTiers" ADD CONSTRAINT "EventPriceTiers_updated_by_one_actor"
  CHECK (NOT ("updated_by_user_id" IS NOT NULL AND "updated_by_admin_id" IS NOT NULL));

-- Two tiers for one event can never cover the same day. Without this, "today's
-- price" would be ambiguous and the answer would depend on row order.
-- btree_gist is already installed by the M0 extensions migration.
ALTER TABLE "EventPriceTiers" ADD CONSTRAINT "EventPriceTiers_no_overlapping_windows"
  EXCLUDE USING gist (
    "event_id" WITH =,
    daterange("starts_on", "ends_on", '[]') WITH &&
  );
```

Then the comments — one `COMMENT ON TABLE` and one `COMMENT ON COLUMN` for every column of both tables, text copied from the `///` doc comment above each field in Step 1. `npm run db:check-comments` in Step 4 is what proves none were missed.

- [ ] **Step 4: Apply and verify**

Run:
```bash
cd backend && npx prisma migrate dev && npx prisma migrate status && npm run db:check-comments
```
Expected: applied, no drift, zero missing comments.

- [ ] **Step 5: Prove the exclusion constraint actually bites**

Run:
```bash
cd backend && npx prisma db execute --stdin <<'SQL'
BEGIN;
INSERT INTO "Events" ("slug","title","start_at","end_at","visibility","status")
VALUES ('x-test','X', now() + interval '30 days', now() + interval '31 days', 1, 0);
INSERT INTO "EventPriceTiers" ("event_id","name","starts_on","ends_on","member_price","non_member_price")
SELECT id, 'A', current_date, current_date + 10, 1000, 2000 FROM "Events" WHERE slug = 'x-test';
INSERT INTO "EventPriceTiers" ("event_id","name","starts_on","ends_on","member_price","non_member_price")
SELECT id, 'B', current_date + 5, current_date + 15, 1500, 2500 FROM "Events" WHERE slug = 'x-test';
ROLLBACK;
SQL
```
Expected: the **second tier insert fails** with `conflicting key value violates exclusion constraint`. If it succeeds, the constraint is wrong — stop and fix it before going further.

- [ ] **Step 6: Commit**

```bash
git add backend/prisma/schema/event.prisma backend/prisma/migrations
git commit -m "feat(m7): add Events and EventPriceTiers with non-overlapping price windows"
```

---

### Task 2: Event code maps and the two settings

**Files:**
- Create: `backend/src/modules/event/event.constants.ts`
- Modify: `backend/prisma/seed/systemSettings.ts`
- Modify: `backend/src/modules/settings/settings.types.ts` (`EDITABLE_SETTINGS`)
- Test: `backend/src/modules/event/event.reminderDays.test.ts`

**Interfaces:**
- Produces: `EVENT_VISIBILITY`, `EVENT_STATUS`, `reminderDaysFor(holdDays: number): number[]`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/event.reminderDays.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { reminderDaysFor } from '@modules/event/event.constants';

describe('reminderDaysFor', () => {
  it('sends at the midpoint and the day before expiry', () => {
    expect(reminderDaysFor(5)).toEqual([3, 4]);
    expect(reminderDaysFor(7)).toEqual([4, 6]);
  });

  it('collapses to one reminder on a short hold', () => {
    expect(reminderDaysFor(3)).toEqual([2]);
    expect(reminderDaysFor(2)).toEqual([1]);
  });

  it('sends none when there is no day left to warn on', () => {
    expect(reminderDaysFor(1)).toEqual([]);
    expect(reminderDaysFor(0)).toEqual([]);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd backend && npx vitest run src/modules/event/event.reminderDays.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the constants**

Create `backend/src/modules/event/event.constants.ts`:

```ts
/**
 * Integer enum codes and derived numbers for the event module.
 *
 * Codes are `smallint` in the database rather than native enums (spec section
 * 0.1), and they are append-only — old rows keep whatever number was written
 * into them, so a value is never renumbered or reused.
 */

export const EVENT_VISIBILITY = {
  /** Absent from every public query, not merely hidden after fetching. */
  MEMBER_ONLY: 0,
  /** Listed publicly; non-members may register. */
  PUBLIC: 1,
} as const;

export const EVENT_STATUS = {
  /** Being prepared. Invisible to everyone but staff. */
  DRAFT: 0,
  /** Live. The only status in which registration is possible. */
  PUBLISHED: 1,
  /** Called off. Paid registrations are refunded as part of cancelling. */
  CANCELLED: 2,
  /** Finished. Set by a job once end_at has passed. */
  COMPLETED: 3,
} as const;

/**
 * Which days of the payment hold get a reminder email.
 *
 * Derived from the hold length rather than stored as its own setting: with two
 * independent numbers, changing the hold from 5 days to 3 would silently leave a
 * "reminder on day 4" that fires after the seats are already gone.
 *
 * Midpoint, then the day before expiry, de-duplicated. A one-day hold gets none —
 * there is no day left on which a warning would still be useful.
 */
export const reminderDaysFor = (holdDays: number): number[] => {
  if (holdDays < 2) return [];

  const days = new Set<number>();

  days.add(Math.ceil(holdDays / 2));

  if (holdDays - 1 >= 1) days.add(holdDays - 1);

  return [...days].sort((a, b) => a - b);
};
```

- [ ] **Step 4: Run the test**

Run: `cd backend && npx vitest run src/modules/event/event.reminderDays.test.ts`
Expected: PASS, all three cases.

- [ ] **Step 5: Seed the two settings**

In `backend/prisma/seed/systemSettings.ts`, add two rows following the shape the file already uses:

```ts
  {
    key: 'event.payment_hold_days',
    value: '5',
    value_type: SettingValueType.NUMBER,
    group: 'events',
    description: 'How many days a registration holds its seats before the unpaid booking is released. Reminder emails are derived from this number, not configured separately.',
    is_public: false,
  },
  {
    key: 'membership.grace_days',
    value: '30',
    value_type: SettingValueType.NUMBER,
    group: 'membership',
    description: 'How long after expiry a member still gets member pricing on events.',
    is_public: false,
  },
```

Add both keys to `EDITABLE_SETTINGS` in `backend/src/modules/settings/settings.types.ts` with a numeric-string validator matching the existing entries (grep the file for an existing NUMBER-typed key and copy its zod schema exactly). Bound them: hold days 1–30, grace days 0–365. An unbounded hold would let an admin freeze every seat on the platform with one typo.

- [ ] **Step 6: Verify and commit**

Run: `cd backend && npx prisma db seed && npm run typecheck && npx vitest run`
Expected: all pass, both settings rows exist.

```bash
git add backend/src/modules/event backend/prisma/seed/systemSettings.ts backend/src/modules/settings/settings.types.ts
git commit -m "feat(m7): event code maps, derived reminder days, hold and grace settings"
```

---

### Task 3: Price resolution — which price applies today

The single most testable piece of business logic in the module, and the one a bug hurts most. It is written before any endpoint so the rules are pinned down first.

**Files:**
- Create: `backend/src/modules/event/event.pricing.ts`
- Test: `backend/src/modules/event/event.pricing.test.ts`

**Interfaces:**
- Consumes: `EVENT_VISIBILITY` (Task 2).
- Produces:
  - `type PriceTier = { id: bigint; name: string; starts_on: Date; ends_on: Date; member_price: Prisma.Decimal; non_member_price: Prisma.Decimal }`
  - `resolveTier(tiers: PriceTier[], on: Date): PriceTier | null`
  - `type Audience = 'MEMBER' | 'NON_MEMBER'`
  - `audienceFor(input: { membershipValidTill: Date | null; graceDays: number; on: Date }): Audience`
  - `unitPrice(tier: PriceTier, audience: Audience): Prisma.Decimal`

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/event.pricing.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { Prisma } from '@prisma/client';
import { audienceFor, resolveTier, unitPrice } from '@modules/event/event.pricing';

const tier = (
  id: number,
  name: string,
  starts: string,
  ends: string,
  member: string,
  nonMember: string,
) => ({
  id: BigInt(id),
  name,
  starts_on: new Date(`${starts}T00:00:00.000Z`),
  ends_on: new Date(`${ends}T00:00:00.000Z`),
  member_price: new Prisma.Decimal(member),
  non_member_price: new Prisma.Decimal(nonMember),
});

const TIERS = [
  tier(1, 'Early bird', '2026-09-01', '2026-11-15', '1000', '2000'),
  tier(2, 'Regular', '2026-11-16', '2026-12-05', '1500', '2500'),
  tier(3, 'Late', '2026-12-06', '2026-12-10', '2000', '3000'),
];

const at = (iso: string) => new Date(iso);

describe('resolveTier', () => {
  it('picks the window the date falls in', () => {
    expect(resolveTier(TIERS, at('2026-11-10T09:00:00.000Z'))?.name).toBe('Early bird');
    expect(resolveTier(TIERS, at('2026-11-20T09:00:00.000Z'))?.name).toBe('Regular');
  });

  it('keeps the tier until the very end of its last day', () => {
    expect(resolveTier(TIERS, at('2026-11-15T23:55:00.000Z'))?.name).toBe('Early bird');
    expect(resolveTier(TIERS, at('2026-11-16T00:05:00.000Z'))?.name).toBe('Regular');
  });

  it('returns null outside every window rather than guessing a price', () => {
    expect(resolveTier(TIERS, at('2026-08-31T12:00:00.000Z'))).toBeNull();
    expect(resolveTier(TIERS, at('2026-12-11T12:00:00.000Z'))).toBeNull();
  });

  it('returns null when an event has no tiers at all', () => {
    expect(resolveTier([], at('2026-11-10T09:00:00.000Z'))).toBeNull();
  });
});

describe('audienceFor', () => {
  const validTill = new Date('2027-03-31T00:00:00.000Z');

  it('treats a live membership as a member', () => {
    expect(
      audienceFor({ membershipValidTill: validTill, graceDays: 30, on: at('2027-03-01T00:00:00.000Z') }),
    ).toBe('MEMBER');
  });

  it('keeps member pricing inside the grace period', () => {
    expect(
      audienceFor({ membershipValidTill: validTill, graceDays: 30, on: at('2027-04-05T00:00:00.000Z') }),
    ).toBe('MEMBER');
    expect(
      audienceFor({ membershipValidTill: validTill, graceDays: 30, on: at('2027-04-30T00:00:00.000Z') }),
    ).toBe('MEMBER');
  });

  it('drops to non-member pricing once the grace period is over', () => {
    expect(
      audienceFor({ membershipValidTill: validTill, graceDays: 30, on: at('2027-05-02T00:00:00.000Z') }),
    ).toBe('NON_MEMBER');
  });

  it('treats a guest with no membership at all as a non-member', () => {
    expect(
      audienceFor({ membershipValidTill: null, graceDays: 30, on: at('2026-11-10T00:00:00.000Z') }),
    ).toBe('NON_MEMBER');
  });

  it('honours a zero-day grace period', () => {
    expect(
      audienceFor({ membershipValidTill: validTill, graceDays: 0, on: at('2027-04-01T00:00:00.000Z') }),
    ).toBe('NON_MEMBER');
  });
});

describe('unitPrice', () => {
  it('reads the column matching the audience', () => {
    expect(unitPrice(TIERS[0], 'MEMBER').toString()).toBe('1000');
    expect(unitPrice(TIERS[0], 'NON_MEMBER').toString()).toBe('2000');
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd backend && npx vitest run src/modules/event/event.pricing.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

Create `backend/src/modules/event/event.pricing.ts`:

```ts
import { Prisma } from '@prisma/client';

/**
 * Which price applies, and to whom.
 *
 * Kept as pure functions with no database access so every boundary — the last
 * minute of a tier, the last day of the grace period, an event with no tiers —
 * is testable without a fixture. The registration transaction calls these and
 * freezes the answer onto the row; nothing recomputes a price later.
 */

export interface PriceTier {
  id: bigint;
  name: string;
  starts_on: Date;
  ends_on: Date;
  member_price: Prisma.Decimal;
  non_member_price: Prisma.Decimal;
}

export type Audience = 'MEMBER' | 'NON_MEMBER';

/** Midnight UTC at the start of the day `date` falls in. */
const startOfDay = (date: Date): number =>
  Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());

/**
 * The tier covering `on`, or null.
 *
 * Both ends are inclusive and compared by day, not by instant: a tier ending
 * 15 Nov must still apply at 23:55 on 15 Nov, which a naive `on <= ends_on`
 * against a midnight-stamped DATE column would get wrong by a day.
 *
 * Null is a real answer, not a failure — outside every window there is no price,
 * and the caller must refuse the booking rather than invent one.
 */
export const resolveTier = (tiers: PriceTier[], on: Date): PriceTier | null => {
  const day = startOfDay(on);

  return (
    tiers.find((tier) => startOfDay(tier.starts_on) <= day && day <= startOfDay(tier.ends_on)) ??
    null
  );
};

/**
 * Member or non-member price, for a booking made on `on`.
 *
 * A membership that expired inside the grace window still counts as a member: a
 * firm three days late renewing is not an outsider. Past the window it is, and
 * the screen says so with the renew prompt.
 */
export const audienceFor = (input: {
  membershipValidTill: Date | null;
  graceDays: number;
  on: Date;
}): Audience => {
  if (!input.membershipValidTill) return 'NON_MEMBER';

  const graceEnds = startOfDay(input.membershipValidTill) + input.graceDays * 86_400_000;

  return startOfDay(input.on) <= graceEnds ? 'MEMBER' : 'NON_MEMBER';
};

/** The per-delegate price for this tier and audience. */
export const unitPrice = (tier: PriceTier, audience: Audience): Prisma.Decimal =>
  audience === 'MEMBER' ? tier.member_price : tier.non_member_price;
```

- [ ] **Step 4: Run the test**

Run: `cd backend && npx vitest run src/modules/event/event.pricing.test.ts`
Expected: PASS — all 12 cases.

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/event/event.pricing.ts backend/src/modules/event/event.pricing.test.ts
git commit -m "feat(m7): resolve event price by booking date, audience and grace period"
```

---

### Task 4: Admin creates and edits a draft event

**Files:**
- Create: `backend/src/modules/event/event.types.ts`
- Create: `backend/src/modules/event/event.repository.ts`
- Create: `backend/src/modules/event/event.service.ts`
- Create: `backend/src/modules/event/event.controller.ts`
- Create: `backend/src/modules/event/event.routes.ts`
- Modify: `backend/src/routes/index.ts` (mount `eventAdminRouter`)
- Modify: `backend/src/constant/audit.constant.ts`
- Modify: `backend/prisma/seed/permissions.ts`
- Test: `backend/src/modules/event/event.create.test.ts`

**Interfaces:**
- Consumes: `EVENT_STATUS`, `EVENT_VISIBILITY` (Task 2).
- Produces: `createEvent(input: CreateEventInput, actor: Actor): Promise<EventDetail>`, `updateEvent(id: bigint, input: UpdateEventInput, actor: Actor)`, and `createEventSchema` / `updateEventSchema`.

- [ ] **Step 1: Read the shape to copy before writing anything**

Run: `cd backend && sed -n '1,60p' src/modules/masters/masters.routes.ts && grep -n "authorize(" src/modules/masters/masters.routes.ts | head`

Copy that router's audience prefix, `authorize()` usage and validation style exactly. Do not invent a new controller shape.

- [ ] **Step 2: Write the validation schemas**

Create `backend/src/modules/event/event.types.ts`:

```ts
import { z } from 'zod';
import { EVENT_VISIBILITY } from '@modules/event/event.constants';

const priceTierSchema = z
  .object({
    name: z.string().trim().min(1).max(60),
    starts_on: z.coerce.date(),
    ends_on: z.coerce.date(),
    member_price: z.coerce.number().min(0),
    non_member_price: z.coerce.number().min(0),
  })
  .refine((tier) => tier.ends_on >= tier.starts_on, {
    message: 'A price tier cannot end before it starts.',
    path: ['ends_on'],
  });

export const createEventSchema = z
  .object({
    title: z.string().trim().min(3).max(200),
    description: z.string().trim().max(20_000).optional(),
    start_at: z.coerce.date(),
    end_at: z.coerce.date(),
    venue_name: z.string().trim().max(200).optional(),
    venue_address_line1: z.string().trim().max(200).optional(),
    venue_address_line2: z.string().trim().max(200).optional(),
    city: z.string().trim().max(100).optional(),
    state: z.string().trim().max(100).optional(),
    pincode: z.string().trim().max(10).optional(),
    country: z.string().trim().max(100).default('India'),
    map_url: z.string().trim().url().max(2000).optional(),
    visibility: z.nativeEnum(EVENT_VISIBILITY).default(EVENT_VISIBILITY.MEMBER_ONLY),
    tax_rate: z.coerce.number().min(0).max(100).default(0),
    capacity: z.coerce.number().int().positive().nullable().default(null),
    registration_opens_at: z.coerce.date().nullable().default(null),
    registration_closes_at: z.coerce.date().nullable().default(null),
    requires_approval: z.boolean().default(false),
    collect_food_preference: z.boolean().default(true),
    collect_photo: z.boolean().default(false),
    collect_gov_id: z.boolean().default(false),
    price_tiers: z.array(priceTierSchema).min(1),
  })
  .refine((event) => event.end_at > event.start_at, {
    message: 'The event cannot end before it starts.',
    path: ['end_at'],
  })
  .refine(
    (event) => !event.registration_closes_at || event.registration_closes_at <= event.start_at,
    { message: 'Registration must close on or before the event starts.', path: ['registration_closes_at'] },
  )
  .refine((event) => !overlaps(event.price_tiers), {
    message: 'Two price tiers cover the same dates.',
    path: ['price_tiers'],
  });

/**
 * Overlap check in the API layer as well as the database.
 *
 * The exclusion constraint is the real guarantee, but it surfaces as a raw
 * Postgres error the admin screen cannot map to a field. Checking here turns it
 * into a field-level message; the constraint stays as the thing that cannot be
 * bypassed.
 */
const overlaps = (tiers: { starts_on: Date; ends_on: Date }[]): boolean =>
  tiers.some((a, i) =>
    tiers.some((b, j) => i !== j && a.starts_on <= b.ends_on && b.starts_on <= a.ends_on),
  );

export type CreateEventInput = z.infer<typeof createEventSchema>;

export const updateEventSchema = createEventSchema;
export type UpdateEventInput = z.infer<typeof updateEventSchema>;
```

- [ ] **Step 3: Write the failing test**

Create `backend/src/modules/event/event.create.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { createEventSchema } from '@modules/event/event.types';

const base = {
  title: 'Export Summit 2026',
  start_at: '2026-12-15T09:00:00.000Z',
  end_at: '2026-12-15T18:00:00.000Z',
  capacity: 100,
  price_tiers: [
    { name: 'Early bird', starts_on: '2026-09-01', ends_on: '2026-11-15', member_price: 1000, non_member_price: 2000 },
    { name: 'Regular', starts_on: '2026-11-16', ends_on: '2026-12-05', member_price: 1500, non_member_price: 2500 },
  ],
};

describe('createEventSchema', () => {
  it('accepts a well-formed event', () => {
    expect(createEventSchema.safeParse(base).success).toBe(true);
  });

  it('rejects an event that ends before it starts', () => {
    const result = createEventSchema.safeParse({ ...base, end_at: '2026-12-14T09:00:00.000Z' });
    expect(result.success).toBe(false);
  });

  it('rejects two price tiers covering the same day', () => {
    const result = createEventSchema.safeParse({
      ...base,
      price_tiers: [
        { name: 'A', starts_on: '2026-09-01', ends_on: '2026-11-15', member_price: 1000, non_member_price: 2000 },
        { name: 'B', starts_on: '2026-11-15', ends_on: '2026-12-05', member_price: 1500, non_member_price: 2500 },
      ],
    });
    expect(result.success).toBe(false);
  });

  it('rejects an event with no price tier — every event needs a price, free is 0', () => {
    expect(createEventSchema.safeParse({ ...base, price_tiers: [] }).success).toBe(false);
  });

  it('rejects registration closing after the event starts', () => {
    const result = createEventSchema.safeParse({
      ...base,
      registration_closes_at: '2026-12-16T00:00:00.000Z',
    });
    expect(result.success).toBe(false);
  });

  it('defaults a new event to MEMBER_ONLY and DRAFT-safe values', () => {
    const parsed = createEventSchema.parse(base);
    expect(parsed.visibility).toBe(0);
    expect(parsed.requires_approval).toBe(false);
    expect(parsed.collect_food_preference).toBe(true);
  });
});
```

- [ ] **Step 4: Run it and watch it fail**

Run: `cd backend && npx vitest run src/modules/event/event.create.test.ts`
Expected: FAIL — module not found. Then create `event.types.ts` from Step 2 and it should PASS. Run it again to confirm before moving on.

- [ ] **Step 5: Write the repository, service, controller and router**

`event.repository.ts` — `createEventWithTiers(tx, data, tiers, adminId)`, `updateEventWithTiers(tx, id, data, tiers, adminId)`, `findEventById`, `findEventBySlug`, `listEventsAdmin(query)`. Tiers on update are replaced wholesale inside the transaction (delete then insert), because a tier edit is a re-pricing, not a row-by-row patch — and the exclusion constraint would reject an intermediate overlapping state anyway.

`event.service.ts` — `createEvent` generates the slug from the title plus a short random suffix (a title collision must not fail the save), writes event and tiers in one `prisma.$transaction`, writes an audit row, and returns the detail shape. `updateEvent` refuses when `status === EVENT_STATUS.CANCELLED`.

`event.controller.ts` and `event.routes.ts` — mirror `masters.routes.ts`. Admin routes are `authenticateAdmin` + `authorize('event.manage')`.

Mount in `backend/src/routes/index.ts` alongside the other admin routers:

```ts
router.use(`${END_POINTS.V1}${END_POINTS.ADMIN}`, eventAdminRouter);
```

- [ ] **Step 6: Add permissions and audit actions**

In `backend/prisma/seed/permissions.ts`, add `event.view`, `event.manage`, `event.publish` following the existing entry shape, granted to the roles that already hold the equivalent masters permissions.

In `backend/src/constant/audit.constant.ts`:

```ts
  // --- M7: events -----------------------------------------------------------
  /** A draft event was created. */
  EVENT_CREATED: 'event.created',
  /** An event's details or prices were edited. */
  EVENT_UPDATED: 'event.updated',
  /** An event went live to its audience. */
  EVENT_PUBLISHED: 'event.published',
  /** An event was called off. */
  EVENT_CANCELLED: 'event.cancelled',
```

- [ ] **Step 7: Verify and commit**

Run: `cd backend && npm run typecheck && npx vitest run && npx prisma db seed`
Expected: pass. Then `POST /api/v1/admin/events` with the body from the test and confirm a DRAFT event with two tiers comes back.

```bash
git add backend/src/modules/event backend/src/routes/index.ts backend/src/constant/audit.constant.ts backend/prisma/seed/permissions.ts
git commit -m "feat(m7): admin creates and edits draft events with price tiers"
```

---

### Task 5: Publish and cancel

**Files:**
- Modify: `backend/src/modules/event/event.service.ts`
- Modify: `backend/src/modules/event/event.controller.ts`, `event.routes.ts`
- Test: `backend/src/modules/event/event.publish.test.ts`

**Interfaces:**
- Produces: `publishEvent(id, actor)`, `cancelEvent(id, input, actor)`, `audienceSize(visibility): Promise<number>`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/event.publish.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const findEventById = vi.fn();
const updateEventStatus = vi.fn();
const countActiveMembers = vi.fn();
const writeAudit = vi.fn();

vi.mock('@db/prisma', () => ({
  prisma: { $transaction: async (fn: (tx: unknown) => unknown) => fn({}) },
}));
vi.mock('@modules/event/event.repository', () => ({
  findEventById: (...a: unknown[]) => findEventById(...a),
  updateEventStatus: (...a: unknown[]) => updateEventStatus(...a),
  countActiveMembers: (...a: unknown[]) => countActiveMembers(...a),
}));
vi.mock('@utils/audit', () => ({ writeAudit: (...a: unknown[]) => writeAudit(...a) }));

const { publishEvent } = await import('@modules/event/event.service');

const actor = { id: 1n, type: 'ADMIN' as const, ip: '::1', userAgent: 't', requestId: 'r' };

beforeEach(() => {
  vi.clearAllMocks();
  countActiveMembers.mockResolvedValue(1240);
  updateEventStatus.mockResolvedValue({ id: 5n, status: 1 });
});

describe('publishEvent', () => {
  it('publishes a draft and reports the audience it reached', async () => {
    findEventById.mockResolvedValue({ id: 5n, status: 0, visibility: 1, price_tiers: [{ id: 1n }] });

    const result = await publishEvent(5n, actor);

    expect(updateEventStatus.mock.calls[0][2]).toMatchObject({ status: 1 });
    expect(result).toMatchObject({ audience_size: 1240 });
  });

  it('refuses to publish an event with no price tier', async () => {
    findEventById.mockResolvedValue({ id: 5n, status: 0, visibility: 1, price_tiers: [] });

    await expect(publishEvent(5n, actor)).rejects.toThrow(/price/i);
    expect(updateEventStatus).not.toHaveBeenCalled();
  });

  it('refuses to publish an already-published event', async () => {
    findEventById.mockResolvedValue({ id: 5n, status: 1, visibility: 1, price_tiers: [{ id: 1n }] });

    await expect(publishEvent(5n, actor)).rejects.toThrow(/published/i);
  });

  it('refuses to publish a cancelled event', async () => {
    findEventById.mockResolvedValue({ id: 5n, status: 2, visibility: 1, price_tiers: [{ id: 1n }] });

    await expect(publishEvent(5n, actor)).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd backend && npx vitest run src/modules/event/event.publish.test.ts`
Expected: FAIL — `publishEvent is not a function`.

- [ ] **Step 3: Implement**

`publishEvent` loads the event with its tiers, refuses unless `status === DRAFT`, refuses when there are no tiers, flips to `PUBLISHED`, writes the audit row, and returns `{ id, status, audience_size }`. `audience_size` counts ACTIVE members for a member-only event and the same count for a public one — the admin confirmation dialog states it *before* the click, so the service must return it after as the record of what was announced.

`cancelEvent` in this plan only handles an event with **no registrations**, because registrations do not exist yet: it refuses with a clear message if `seats_taken > 0`. Plan 3 replaces that guard with the refund-all flow.

- [ ] **Step 4: Run the test, wire the routes, verify**

`POST /admin/events/:id/publish` and `POST /admin/events/:id/cancel`, both `authorize('event.publish')`.

Run: `cd backend && npx vitest run && npm run typecheck`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/event
git commit -m "feat(m7): publish and cancel an event"
```

---

### Task 6: Public and member listings — visibility that actually hides

**Files:**
- Modify: `backend/src/modules/event/event.repository.ts`, `event.service.ts`, `event.controller.ts`, `event.routes.ts`
- Modify: `backend/src/routes/index.ts` (mount the public router)
- Test: `backend/src/modules/event/event.visibility.test.ts`

**Interfaces:**
- Produces: `listPublicEvents(query)`, `listMemberEvents(query)`, `getPublicEvent(slug)`, `getMemberEvent(slug, userId)`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/event.visibility.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const queryRaw = vi.fn();

vi.mock('@db/prisma', () => ({ prisma: { $queryRaw: (...a: unknown[]) => queryRaw(...a) } }));

const { listPublicEvents, getPublicEvent } = await import('@modules/event/event.service');

beforeEach(() => {
  vi.clearAllMocks();
  queryRaw.mockResolvedValue([]);
});

describe('public event queries', () => {
  it('filters to PUBLISHED and PUBLIC in SQL, not after fetching', async () => {
    await listPublicEvents({ page: 1, limit: 20 });

    const sql = JSON.stringify(queryRaw.mock.calls[0][0]);
    expect(sql).toContain('visibility');
    expect(sql).toContain('status');
  });

  it('returns null for a members-only event asked for by slug', async () => {
    queryRaw.mockResolvedValue([]);

    await expect(getPublicEvent('agm-2026')).resolves.toBeNull();
  });
});
```

- [ ] **Step 2: Run it and watch it fail, then implement**

The public list statement filters `status = 1 AND visibility = 1 AND "deletedAt" IS NULL`. The member list filters `status = 1` only — a member sees both member-only and public events. Both order by `start_at ASC` and page with a windowed count, matching `listInvoicesAdmin` in `member.service.ts`.

`getPublicEvent(slug)` returns `null`, not a 403, when the event is member-only. A 403 confirms the event exists; a members-only AGM should be indistinguishable from a typo.

The detail response includes the full tier table and a computed `current_price` block:

```ts
{
  tier_name: 'Early bird',
  member_price: '1000.00',
  non_member_price: '2000.00',
  applies_until: '2026-11-15',
  seats_left: 63,        // capacity - seats_taken, or null when unlimited
  registration_open: true
}
```

using `resolveTier` from Task 3. When `resolveTier` returns null, `current_price` is `null` and `registration_open` is `false` — never a fallback price.

- [ ] **Step 3: Mount the routes**

- `GET /api/v1/public/events` and `GET /api/v1/public/events/:slug` — no auth.
- `GET /api/v1/events` and `GET /api/v1/events/:slug` — `authenticate`.

- [ ] **Step 4: Verify the hiding by hand — this is the security-relevant check**

Create one member-only published event and one public published event, then:

```bash
curl -s localhost:<port>/api/v1/public/events | grep -c "agm"      # expect 0
curl -s localhost:<port>/api/v1/public/events/agm-2026            # expect 404
```
Expected: the member-only event appears in neither. If it 403s instead of 404s, fix it — the status code itself leaks the event's existence.

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/event backend/src/routes/index.ts
git commit -m "feat(m7): public and member event listings with real visibility filtering"
```

---

### Task 7: Self-test suite entry

**Files:**
- Modify: `backend/src/routes/selftest/selftest.routes.ts`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Read the existing suite shape**

Run: `cd backend && sed -n '1,80p' src/routes/selftest/selftest.routes.ts`

Follow the existing per-module key pattern exactly. Use the existing Self-Test Agent; per CLAUDE.md, do not create another testing agent.

- [ ] **Step 2: Add an `event` suite covering what this plan built**

Assertions, in the spec's words:
- publishing a member-only event makes it visible to members and **absent** from the public list;
- publishing a public event makes it visible to both;
- a draft event is invisible to both;
- the price shown on 15 Nov is the early-bird price and on 16 Nov the regular price;
- an event with no price tier cannot be published;
- two overlapping tiers are rejected by the database, not only by the API.

- [ ] **Step 3: Run it and commit**

```bash
git add backend/src/routes/selftest
git commit -m "test(m7): event core self-test suite"
```

---

### Task 8: Admin screens A-21 and A-22

**Files:**
- Create: `admin/src/pages/events/EventList.tsx`, `admin/src/pages/events/EventForm.tsx`, `admin/src/pages/events/PriceTierEditor.tsx`
- Modify: the admin route table and the left-nav "Engage" group

**Interfaces:**
- Consumes: the admin endpoints from Tasks 4 and 5.

- [ ] **Step 1: Invoke the `association-admin-ui` skill first**

This is mandatory per CLAUDE.md and is the reason a new page looks like the existing ones. Build from the catalogue's table, search, select, drawer, confirm, cells and tokens. No direct `antd` imports for Table/Select/Button/Modal/Pagination; no page sets a colour, radius, height or font-size.

- [ ] **Step 2: Event list (A-21)**

Columns: title, dates, city, visibility chip, status chip, capacity as `seats_taken / capacity`. Filters: status, visibility, date range. Empty state per the catalogue.

- [ ] **Step 3: Event form with the price tier editor**

The tier editor is a repeating row — name, from, to, member price, non-member price — with an **Add tier** action. It must show the overlap error against the offending row, not as a page-level toast, since the API returns it at `price_tiers`.

The three delegate toggles (food preference, photo, government ID) and the approval checkbox live on this form, each with a one-line plain-language explanation of what it changes for the person registering.

- [ ] **Step 4: Publish confirmation**

The confirm dialog must state the audience **before** the click, per the spec and CLAUDE.md's Current State → Required Action → Next Step → Expected Result rule:

> "This becomes visible to **1,240 members** and to the **public**. Registration opens 01 Sep 2026. Continue?"

- [ ] **Step 5: Verify in the browser and commit**

Create, price, publish and cancel an event through the UI only.

```bash
git add admin/src
git commit -m "feat(m7): admin event list, form and price tier editor"
```

---

### Task 9: Customer screens C-04 and the member event list

**Files:**
- Create: `customer/src/app/(public)/events/page.tsx`, `customer/src/app/(public)/events/[slug]/page.tsx`
- Create: `customer/src/app/(member)/events/page.tsx`, `customer/src/app/(member)/events/[slug]/page.tsx`

Both directories already exist — read what is in them before adding files.

**Interfaces:**
- Consumes: the public and member endpoints from Task 6.

- [ ] **Step 1: Read the existing pages first**

Run: `cd customer && find src/app/\(public\)/events src/app/\(member\)/events -type f`

- [ ] **Step 2: Build the listing and detail pages**

The detail page shows the full tier table with today's row highlighted, and one clear line above the Register button:

- in a tier: *"Members ₹1,000 per person. Early-bird price ends 15 Nov."*
- expired membership inside grace: *"Your membership expired on 31 Mar. Renew within 25 days to keep member pricing."*
- outside every tier: *"Registration is not open for this event."* and **no** price.

Register is not built in this plan — the button is present and disabled with the reason shown, so the page is honest rather than dead.

- [ ] **Step 3: Verify and commit**

Check as a signed-out visitor that a member-only event 404s, and as a member that it appears.

```bash
git add customer/src
git commit -m "feat(m7): public and member event listing and detail pages"
```

---

## Self-review

**Spec coverage.** Design section 1 settings → Task 2. Section 3 create-event form incl. approval checkbox and the three toggles → Tasks 1, 4, 8. Publish and its audience statement → Tasks 5, 8. Section 8 member-only visibility → Tasks 1, 6, 9. Section 9 grace period → Task 3. Section 15 per-event toggles → Tasks 1, 4, 8. Schema section 0 conventions → Task 1. Section 2 `Events` + `EventPriceTiers` → Task 1.

**Deliberately out of scope, covered by Plan 3:** registration, attendees, guest registrants, invoicing, approval queue, payment submission and verification, the hold-expiry job, attendee export. The `seats_taken` column, the `requires_approval` flag, the three toggles and the derived `reminderDaysFor` all ship here so Plan 3 adds behaviour rather than re-migrating tables.

**Two blockers Plan 3 must resolve first**, both stated at the top of this plan: `Invoice.member_id` is NOT NULL so guests cannot be invoiced, and there is no `Payments` table for `PaymentSubmissions.payment_id` to reference. Both need a decision before Plan 3 is written.

**Type consistency check.** `resolveTier` / `audienceFor` / `unitPrice` (Task 3) are used by name in Task 6's `current_price` block. `EVENT_STATUS` / `EVENT_VISIBILITY` (Task 2) are used in Tasks 4, 5 and 6. `createEventSchema` (Task 4) is the body validated in Task 8's form.
