# M6 Membership Renewal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Members renew without anyone chasing them: a renewal term + invoice is raised 15 days before expiry at the member's own plan's renewal price, reminders go out at 15/7/3/0 days, early payment waits as `PAID_UPCOMING`, grace lasts `membership.grace_days`, and the member becomes `EXPIRED` after grace.

**Architecture:** A new backend module `modules/renewal` holds pure date/price/state helpers, one "raise a renewal" transaction, four lifecycle steps run by one hourly job, admin endpoints (buckets + run now) and member endpoints (term view, history, plan switch). The existing payment hook `activateMembershipForInvoice` learns `PAID_UPCOMING`, renew-from-expired and `current_term_id`. Admin gets an A-20 Renewals page; customer gets a banner in the member shell and a `/application/membership` page (C-18/C-23).

**Tech Stack:** Node + Express + TypeScript, Prisma + PostgreSQL (hand-written SQL migrations), Vitest (unit, mocked DB), node-cron; admin React + Vite + TS (`@/components/ui`); customer Next.js 14 + TS (`@/components/ui`, Tailwind tokens).

**Spec:** `docs/modules/M6-renewal.md` (frozen contracts, decided table) and `docs/renewal-module-summary.md` (worked examples). Pricing rules: `docs/specs/2026-09-07-membership-fee-plans.md` §7 (price_scope).

## Global Constraints

- **Git:** work on the branch already checked out in each repo — `backend/`, `admin/`, `customer/` are separate repos (`feature/registration-application-flow-*`). **Never create a branch. Never commit** — every "Checkpoint" step stops for the user, who commits.
- **Dev servers:** never kill running dev servers or delete `.next` / `dist`.
- **Migrations:** new migrations only; never edit an applied one. Every new table/column gets `COMMENT ON` in the **same** migration (ADR-013, `npm run db:check-comments` must return zero rows). Enum values are added in their **own** migration.
- **Dates:** a `@db.Date` value is handled as a UTC-midnight `Date`. "Today" is the server's local calendar day (same convention as `planTerm`). Use the helpers from Task 2 — never `new Date()` arithmetic inline.
- **Money:** `Prisma.Decimal`, tax per line rounded to 2 dp, then summed. Never a float. A renewal price ≤ 0 is "no price": skip and report, never raise a ₹0 invoice.
- **Idempotency:** the DB enforces it — partial unique `(member_id, valid_from) WHERE status <> 'CANCELLED'` and unique `(term_id, reminder_code)`. Code checks first; constraints are the backstop.
- **Decided rules (do not change):** notice 15 days (`membership.renewal_notice_days`); reminders `T-15`, `T-7`, `T-3`, `T-0`; renewal basis = System Settings `billing.renewal_basis`; price = member's own plan's renewal price, moving to a live same-cycle plan only if that plan's `price_scope = ALL_MEMBERS`; no member self-renew before the invoice exists; plan switch allowed until the renewal invoice is paid; admin "Generate Invoices" = run the job now (only members inside the window are billed); grace = `membership.grace_days` only, no per-member extension; after grace → member `EXPIRED`, can still log in and pay.
- **Admin UI:** use the `association-admin-ui` skill before writing any admin screen; components from `@/components/ui` only; Title Case labels, sentence-case messages; `PageHeader title` = nav label.
- **Customer UI:** no `antd` Button/Input/Card/Alert/Modal (use `@/components/ui`), no raw colours; copy is second person and states the consequence.
- **Tests:** backend `npm test` (Vitest), `npm run typecheck`, `npm run lint`. Admin `npm run typecheck && npm run lint`. Customer `npm run typecheck && npm run lint` + `npm run verify:renewal`.
- **Self-test:** the existing Self-Test Agent (`sarvadhi-sentinel/`) owns the `renewal` suite (Task 15). Do not create another testing agent.

## Ownership

| Agent | Tasks |
|---|---|
| Agent B — backend + admin | 1–12, then 17 |
| Agent A — customer | 13–14 (start after Task 1; API contract is frozen in Task 11), then 18 |

Execution order: 1 → 12, 13 → 14, 17, 18, 15, 16.
| Self-Test Agent (Sentinel) | 15 |
| Planning (docs) | 16 |

## File map

**Backend (`backend/`)**
| File | Responsibility |
|---|---|
| `prisma/schema/application.prisma` | `TermStatus.PAID_UPCOMING`, `RenewalReminder` model, relation on `MembershipTerm` |
| `prisma/migrations/20260910090000_m6_term_status_paid_upcoming/migration.sql` | enum value only |
| `prisma/migrations/20260910090100_m6_renewal/migration.sql` | `RenewalReminders`, partial unique on terms, comments |
| `prisma/seed/systemSettings.ts` · `src/helpers/settings.ts` · `src/modules/settings/settings.types.ts` | `membership.renewal_notice_days` |
| `prisma/seed/notificationTemplates.ts` | `membership.renewal_reminder`, `membership.expired` |
| `src/modules/renewal/renewal.dates.ts` | calendar-day helpers + `planRenewalTerm` |
| `src/modules/renewal/renewal.pricing.ts` | `pickRenewalPlan`, `loadRenewalPlan`, `priceRenewal` |
| `src/modules/renewal/renewal.state.ts` | `reminderStageFor`, `termState` (pure) |
| `src/modules/renewal/renewal.raise.ts` | `raiseRenewal(tx, …)` — one term + one invoice |
| `src/modules/renewal/renewal.notify.ts` | queue reminder / expired messages |
| `src/modules/renewal/renewal.repository.ts` | raw SQL: due candidates, reminder candidates, buckets |
| `src/modules/renewal/renewal.lifecycle.ts` | `closeEndedTerms`, `startPaidTerms`, `expireLapsedMembers`, `raiseDueRenewals`, `sendRenewalReminders`, `runRenewalCycle` |
| `src/modules/renewal/renewal.member.service.ts` | term view, history, plans, plan switch |
| `src/modules/renewal/renewal.admin.service.ts` | summary, bucket list, run now |
| `src/modules/renewal/renewal.types.ts` | zod schemas + response types |
| `src/modules/renewal/renewal.controller.ts` · `renewal.routes.ts` | HTTP |
| `src/modules/billing/membershipActivation.ts` | payment hook: `PAID_UPCOMING`, renew-from-expired, `current_term_id` |
| `src/jobs/definitions.ts` | `membership.renewal` hourly job |
| `src/modules/member/member.repository.ts` | admin detail gets `current_term` |
| `src/routes/index.ts` · `src/locales/en.json` | mount routers, messages |

**Admin (`admin/`)**: `src/pages/renewals/Renewals.tsx` (new), `src/services/renewalsService.ts` (new), `src/constant/endpoints.ts`, `src/constant/navigation.tsx`, `src/routes/AppRoutes.tsx`, `src/constant/status.ts`, `src/pages/reports/reportSpecs.ts`, `src/pages/settings/SystemSettings.tsx`, `src/pages/members/ProfileTab.tsx`, `src/services/membersService.ts`.

**Customer (`customer/`)**: `src/types/renewal.ts`, `src/services/RenewalService.ts`, `src/constants/endpoints.ts`, `src/components/renewal/renewalCopy.ts`, `src/components/renewal/MembershipBanner.tsx`, `src/components/renewal/MembershipTermView.tsx`, `src/app/(member)/application/membership/page.tsx`, `src/components/layout/MemberShell.tsx`, `src/components/ui/statusMap.ts`, `src/components/billing/InvoiceList.tsx`, `scripts/verify-renewal.ts`, `package.json`.

---

### Task 1: Schema, migrations, setting, templates

**Files:**
- Modify: `backend/prisma/schema/application.prisma` (enum `TermStatus` ~:89, model `MembershipTerm` ~:623)
- Create: `backend/prisma/migrations/20260910090000_m6_term_status_paid_upcoming/migration.sql`
- Create: `backend/prisma/migrations/20260910090100_m6_renewal/migration.sql`
- Modify: `backend/src/helpers/settings.ts` (`SETTING_KEYS` :78–136)
- Modify: `backend/prisma/seed/systemSettings.ts` (after `membership.grace_days` :97)
- Modify: `backend/src/modules/settings/settings.types.ts` (`EDITABLE_SETTINGS`, after `'membership.grace_days'`)
- Modify: `backend/prisma/seed/notificationTemplates.ts` (after the `membership.payment_*` block ~:610)
- Modify: `backend/src/locales/en.json` (`renewal` namespace :196)

**Interfaces:**
- Produces: `TermStatus.PAID_UPCOMING`; Prisma model `renewalReminder` (`term_id`, `reminder_code`, `sent_on`); `SETTING_KEYS.RENEWAL_NOTICE_DAYS = 'membership.renewal_notice_days'`; templates `membership.renewal_reminder` and `membership.expired` (EMAIL + IN_APP) with variables `name, headline, plan_name, amount, invoice_number, expires_on, due_on` / `name, expired_on`; message keys `renewal.noPendingRenewal|claimPending|planNotAvailable|samePlan|planChanged|runCompleted`.

- [ ] **Step 1: Pre-check existing data** (the partial unique index would fail on duplicates)

Run in `backend/`:
```bash
npx prisma db execute --stdin <<'SQL'
SELECT member_id, valid_from, COUNT(*) FROM "MembershipTerms"
WHERE status <> 'CANCELLED' GROUP BY 1,2 HAVING COUNT(*) > 1;
SQL
```
Expected: no rows. If rows appear, STOP and report them to the user — do not delete data.

- [ ] **Step 2: Edit the schema**

In `application.prisma`, enum `TermStatus`, insert between `PENDING_PAYMENT` and `ACTIVE`:
```prisma
  /// Paid before its start date. Becomes ACTIVE on valid_from (the renewal job's start step);
  /// needed because a member may hold only one ACTIVE term and the current one is still running.
  PAID_UPCOMING
```
In `model MembershipTerm`, add after the `current_for` relation:
```prisma
  /// Renewal reminders sent for this (renewal) term, one per stage.
  reminders RenewalReminder[]
```
Add a new model at the end of `application.prisma`:
```prisma
/// One renewal reminder sent for one renewal term at one stage (T-15, T-7, T-3, T-0). Exists so a
/// job that runs twice cannot send the same reminder twice: the unique (term_id, reminder_code)
/// makes the second insert a no-op, and a message is queued only when the insert happened.
model RenewalReminder {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// FK to MembershipTerms.id — the unpaid renewal term the reminder is about. ON DELETE CASCADE.
  term_id BigInt

  /// Stage: 'T-15', 'T-7', 'T-3' or 'T-0' (days before the current term ends). CHECK-constrained.
  reminder_code String @db.VarChar(10)

  /// Calendar day the reminder was sent (server's local day).
  sent_on DateTime @db.Date

  /// Row creation timestamp (UTC).
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// The renewal term reminded about.
  term MembershipTerm @relation(fields: [term_id], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@unique([term_id, reminder_code])
  @@map("RenewalReminders")
}
```

- [ ] **Step 3: Enum migration (own file, own transaction)**

`prisma/migrations/20260910090000_m6_term_status_paid_upcoming/migration.sql`:
```sql
-- M6 — renewal. Must run in its own migration: PostgreSQL requires an enum addition to
-- commit before the new value can be used (by the partial index in the next migration).
ALTER TYPE "TermStatus" ADD VALUE IF NOT EXISTS 'PAID_UPCOMING' AFTER 'PENDING_PAYMENT';
```

- [ ] **Step 4: Renewal migration**

`prisma/migrations/20260910090100_m6_renewal/migration.sql`:
```sql
-- M6 — membership renewal.
-- Spec: docs/modules/M6-renewal.md · docs/renewal-module-summary.md (decisions 2026-09-10)
--
-- Two guards the renewal job relies on. Both are enforced by the database, not the code:
-- code can forget to check, a constraint cannot.

-- ============================================================================
-- Tables
-- ============================================================================

CREATE TABLE "RenewalReminders" (
  "id"            BIGSERIAL      PRIMARY KEY,
  "term_id"       BIGINT         NOT NULL,
  "reminder_code" VARCHAR(10)    NOT NULL,
  "sent_on"       DATE           NOT NULL,
  "createdAt"     TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "RenewalReminders_term_id_fkey" FOREIGN KEY ("term_id")
    REFERENCES "MembershipTerms"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "RenewalReminders_code_known"
    CHECK ("reminder_code" IN ('T-15', 'T-7', 'T-3', 'T-0'))
);

-- One reminder per stage per term: a second job run inserts nothing and sends nothing.
CREATE UNIQUE INDEX "RenewalReminders_term_id_reminder_code_key"
  ON "RenewalReminders"("term_id", "reminder_code");

-- ============================================================================
-- Terms: one live term per member per start date
--
-- A renewal job that runs twice (restart, retry, the admin's "Generate Invoices") must not
-- bill a member twice. CANCELLED is excluded on purpose: switching plan before paying cancels
-- the renewal term and creates a new one with the SAME start date.
-- ============================================================================

CREATE UNIQUE INDEX "MembershipTerms_one_live_term_per_start"
  ON "MembershipTerms"("member_id", "valid_from") WHERE "status" <> 'CANCELLED';

-- ============================================================================
-- Table & column comments (ADR-013 / database-design.md §I)
-- Generated from the /// doc-comments in prisma/schema/*.prisma by
--   npx tsx scripts/emit-db-comments.ts RenewalReminders
-- ============================================================================
```
Then append the generated block:
```bash
cd backend && npx tsx scripts/emit-db-comments.ts RenewalReminders >> prisma/migrations/20260910090100_m6_renewal/migration.sql
```
Open the file and confirm it ends with `COMMENT ON TABLE "RenewalReminders"` plus one `COMMENT ON COLUMN` for each of the 5 columns.

- [ ] **Step 5: Apply and verify**

```bash
cd backend && npx prisma migrate dev && npx prisma generate && npm run db:check-comments
```
Expected: both migrations applied, client generated, check-comments prints zero offending rows. If `migrate dev` reports drift for `MembershipTerms_one_live_term_per_start`, that is the same situation as the existing `MembershipTerms_one_active_per_member` partial index — do not let Prisma drop it; answer "no" to any reset prompt and report to the user.

- [ ] **Step 6: Setting**

`src/helpers/settings.ts`, inside `SETTING_KEYS` next to `MEMBERSHIP_GRACE_DAYS`:
```ts
  /** Days before a term ends that its renewal term + invoice are raised (M6, decided 2026-09-10). */
  RENEWAL_NOTICE_DAYS: 'membership.renewal_notice_days',
```
`prisma/seed/systemSettings.ts`, after the `membership.grace_days` entry:
```ts
  {
    key: 'membership.renewal_notice_days',
    value: '15',
    value_type: SettingValueType.NUMBER,
    group: 'membership',
    description:
      'How many days before a membership ends its renewal invoice is raised. Reminders follow at 7 and 3 days and on the last day. With invoice due days at 15 the invoice falls due on the expiry date.',
    is_public: false,
  },
```
`src/modules/settings/settings.types.ts`, after `'membership.grace_days': wholeNumber(0, 365),`:
```ts
  // At least a day, or nobody is billed before their term ends. Capped at 90: a longer notice
  // would bill a monthly member for next month before this one has started.
  'membership.renewal_notice_days': wholeNumber(1, 90),
```
Run `cd backend && npx prisma db seed` (the seed upserts and never overwrites an existing value).

- [ ] **Step 7: Templates**

In `prisma/seed/notificationTemplates.ts`, add after the `membership.payment_rejected` template(s). Mirror the channel/field shape of the existing `application.approved` EMAIL + IN_APP pair exactly:
```ts
  /* --- M6: renewal ---------------------------------------------------------
     One template for all four reminder stages: the stage sentence arrives as {{headline}},
     so the four messages cannot drift apart in anything but the sentence that differs. */
  {
    code: 'membership.renewal_reminder',
    channel: NotificationChannel.EMAIL,
    locale: 'en',
    subject: '{{headline}}',
    body: [
      'Hello {{name}},',
      '',
      '{{headline}}',
      '',
      'Plan: {{plan_name}}',
      'Invoice: {{invoice_number}} for {{amount}}, due {{due_on}}',
      'Your current membership ends on {{expires_on}}.',
      '',
      'Pay from the Billing page of your account. Renewing on time keeps your',
      'directory listing and member event pricing without a break.',
    ].join('\n'),
  },
  {
    code: 'membership.renewal_reminder',
    channel: NotificationChannel.IN_APP,
    locale: 'en',
    subject: '{{headline}}',
    body: 'Invoice {{invoice_number}} for {{amount}} is due {{due_on}}. Your membership ends on {{expires_on}}.',
  },
  {
    code: 'membership.expired',
    channel: NotificationChannel.EMAIL,
    locale: 'en',
    subject: 'Your membership has expired',
    body: [
      'Hello {{name}},',
      '',
      'Your membership ended on {{expired_on}} and the grace period has now passed.',
      'Your company is no longer listed in the member directory, and events are',
      'charged at the non-member price.',
      '',
      'You can still sign in. Pay your renewal invoice from the Billing page and',
      'both come back straight away.',
    ].join('\n'),
  },
  {
    code: 'membership.expired',
    channel: NotificationChannel.IN_APP,
    locale: 'en',
    subject: 'Your membership has expired',
    body: 'Pay your renewal invoice to return to the directory and member event pricing.',
  },
```
Run `cd backend && npx tsx scripts/reseed-templates.ts`.

- [ ] **Step 8: Messages** — in `src/locales/en.json`, extend the `renewal` object (keep existing keys):
```json
    "noPendingRenewal": "There is no renewal invoice waiting to be paid",
    "claimPending": "Your payment is being checked, so the plan can't be changed right now",
    "planNotAvailable": "That plan is not available",
    "samePlan": "You are already renewing on this plan",
    "planChanged": "Plan changed. Your renewal invoice has been reissued",
    "runCompleted": "Renewal run completed"
```

- [ ] **Step 9: Verify** — `cd backend && npm run typecheck && npm test`. Expected: PASS (no behaviour changed yet).

- [ ] **Step 10: Checkpoint** — stop; tell the user Task 1 is ready to commit in `backend/`. Do not commit.

---

### Task 2: Calendar-day helpers and `planRenewalTerm`

**Files:**
- Create: `backend/src/modules/renewal/renewal.dates.ts`
- Test: `backend/src/modules/renewal/renewal.dates.test.ts`

**Interfaces:**
- Consumes: `planTerm`, `TermWindow` from `@helpers/membershipTerm`; `RenewalBasis` from `@helpers/settings`.
- Produces: `dbToday(now?: Date): Date`, `addDays(day: Date, n: number): Date`, `daysBetween(from: Date, to: Date): number`, `isoDay(day: Date): string`, `planRenewalTerm(p: { from: Date; durationMonths: number; basis: RenewalBasis }): TermWindow` — all dates UTC-midnight calendar days.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { addDays, daysBetween, dbToday, isoDay, planRenewalTerm } from '@modules/renewal/renewal.dates';

const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);

describe('renewal dates', () => {
  it('dbToday is the local calendar day as a UTC-midnight date', () => {
    const now = new Date(2027, 2, 16, 23, 59); // 16 Mar 2027, local
    expect(isoDay(dbToday(now))).toBe('2027-03-16');
  });

  it('adds and counts whole days', () => {
    expect(isoDay(addDays(day('2027-03-31'), 1))).toBe('2027-04-01');
    expect(daysBetween(day('2027-03-16'), day('2027-03-31'))).toBe(15);
  });

  it('yearly renewal under financial_year runs 1 Apr to 31 Mar, full price', () => {
    const w = planRenewalTerm({ from: day('2027-04-01'), durationMonths: 12, basis: 'financial_year' });
    expect(isoDay(w.validFrom)).toBe('2027-04-01');
    expect(isoDay(w.validTill)).toBe('2028-03-31');
    expect(w.prorated).toBe(false);
  });

  it('quarterly renewal crossing 31 March is cut and prorated by whole months', () => {
    const w = planRenewalTerm({ from: day('2027-03-12'), durationMonths: 3, basis: 'financial_year' });
    expect(isoDay(w.validTill)).toBe('2027-03-31');
    expect(w.months).toBe(1);
    expect(w.prorated).toBe(true);
  });

  it('monthly renewal under term runs to the day before the next anniversary', () => {
    const w = planRenewalTerm({ from: day('2026-10-12'), durationMonths: 1, basis: 'term' });
    expect(isoDay(w.validTill)).toBe('2026-11-11');
    expect(w.prorated).toBe(false);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npx vitest run src/modules/renewal/renewal.dates.test.ts`
Expected: FAIL — cannot resolve `@modules/renewal/renewal.dates`.

- [ ] **Step 3: Implement**

```ts
import { planTerm, type TermWindow } from '@helpers/membershipTerm';
import type { RenewalBasis } from '@helpers/settings';

/**
 * Calendar days for renewal.
 *
 * A `@db.Date` column reads back as UTC midnight, while `planTerm` does its arithmetic on the
 * local calendar. Every renewal date passes through here so the two never meet raw: the day the
 * admin would name is the day that is stored, whatever timezone the server runs in.
 */

export const DAY_MS = 86_400_000;

/** Today on the server's local calendar, as the UTC-midnight Date a DATE column stores. */
export const dbToday = (now: Date = new Date()): Date =>
  new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));

export const addDays = (day: Date, n: number): Date => new Date(day.getTime() + n * DAY_MS);

/** Whole days from `from` to `to` (negative when `to` is earlier). */
export const daysBetween = (from: Date, to: Date): number =>
  Math.round((to.getTime() - from.getTime()) / DAY_MS);

export const isoDay = (day: Date): string => day.toISOString().slice(0, 10);

const toLocal = (day: Date): Date =>
  new Date(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate());

const toDb = (local: Date): Date =>
  new Date(Date.UTC(local.getFullYear(), local.getMonth(), local.getDate()));

/**
 * `planTerm` for a renewal. Same arithmetic as joining — two copies of a pro-rata rule is how a
 * member ends up billed differently for joining than for renewing — with the dates converted in
 * and out so a DATE column's UTC midnight never lands on the wrong local day.
 */
export const planRenewalTerm = (params: {
  from: Date;
  durationMonths: number;
  basis: RenewalBasis;
}): TermWindow => {
  const window = planTerm({
    from: toLocal(params.from),
    durationMonths: params.durationMonths,
    basis: params.basis,
  });

  return { ...window, validFrom: toDb(window.validFrom), validTill: toDb(window.validTill) };
};
```

- [ ] **Step 4: Run to verify it passes** — same command. Expected: 5 passed.

- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 3: Renewal pricing

**Files:**
- Create: `backend/src/modules/renewal/renewal.pricing.ts`
- Test: `backend/src/modules/renewal/renewal.pricing.test.ts`

**Interfaces:**
- Consumes: `CYCLE_MONTHS` from `@modules/masters/masters.feePlans.service`; `TermWindow`.
- Produces:
  - `type RenewalPlan = { id: bigint; billing_cycle: BillingCycle; name: string; renewal_amount: Prisma.Decimal; tax_rate: Prisma.Decimal; currency: string; effective_from: Date; effective_to: Date | null; is_active: boolean; price_scope: PriceScope }`
  - `isLiveOn(plan: RenewalPlan, day: Date): boolean`
  - `pickRenewalPlan(own: RenewalPlan, liveSameCycle: RenewalPlan | null, day: Date): RenewalPlan`
  - `loadRenewalPlan(db: Db, feePlanId: bigint, day: Date): Promise<RenewalPlan | null>`
  - `loadLivePlan(db: Db, feePlanId: bigint, day: Date): Promise<RenewalPlan | null>` (plan switch target — must be live today)
  - `priceRenewal(amount: Prisma.Decimal, taxRate: Prisma.Decimal, window: TermWindow): { net; tax; total }`
  - `durationOf(plan: RenewalPlan): number` = `CYCLE_MONTHS[plan.billing_cycle]`

- [ ] **Step 1: Write the failing test**

```ts
import { Prisma } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { pickRenewalPlan, priceRenewal, type RenewalPlan } from '@modules/renewal/renewal.pricing';

const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);
const D = (v: string) => new Prisma.Decimal(v);

const plan = (over: Partial<RenewalPlan>): RenewalPlan => ({
  id: 1n,
  billing_cycle: 'YEARLY',
  name: 'Best Value',
  renewal_amount: D('20000'),
  tax_rate: D('18'),
  currency: 'INR',
  effective_from: day('2026-04-01'),
  effective_to: null,
  is_active: true,
  price_scope: 'ALL_MEMBERS',
  ...over,
});

describe('pickRenewalPlan', () => {
  it('keeps the member on their own plan while it is live', () => {
    const own = plan({ id: 1n });
    expect(pickRenewalPlan(own, plan({ id: 2n }), day('2027-03-16')).id).toBe(1n);
  });

  it('moves to the live same-cycle plan when it applies to all members', () => {
    const own = plan({ id: 1n, is_active: false, effective_to: day('2026-12-31') });
    const live = plan({ id: 2n, renewal_amount: D('22000'), price_scope: 'ALL_MEMBERS' });
    expect(pickRenewalPlan(own, live, day('2027-03-16')).id).toBe(2n);
  });

  it('stays on the closed plan when the new price is for new members only', () => {
    const own = plan({ id: 1n, is_active: false, effective_to: day('2026-12-31') });
    const live = plan({ id: 2n, price_scope: 'NEW_MEMBERS_ONLY' });
    expect(pickRenewalPlan(own, live, day('2027-03-16')).id).toBe(1n);
  });

  it('stays on the closed plan when nothing is live for the cycle', () => {
    const own = plan({ id: 1n, is_active: false });
    expect(pickRenewalPlan(own, null, day('2027-03-16')).id).toBe(1n);
  });
});

describe('priceRenewal', () => {
  it('charges the full renewal price plus tax on a full term', () => {
    const p = priceRenewal(D('20000'), D('18'), { months: 12, durationMonths: 12, prorated: false } as never);
    expect(p.total.toFixed(2)).toBe('23600.00');
  });

  it('prorates by whole months and taxes the prorated line', () => {
    const p = priceRenewal(D('7000'), D('18'), { months: 1, durationMonths: 3, prorated: true } as never);
    expect(p.net.toFixed(2)).toBe('2333.33');
    expect(p.tax.toFixed(2)).toBe('420.00');
    expect(p.total.toFixed(2)).toBe('2753.33');
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/modules/renewal/renewal.pricing.test.ts` → FAIL (module missing).

- [ ] **Step 3: Implement**

```ts
import { Prisma, type BillingCycle, type PriceScope } from '@prisma/client';
import type { Db } from '@db/prisma';
import type { TermWindow } from '@helpers/membershipTerm';
import { CYCLE_MONTHS } from '@modules/masters/masters.feePlans.service';

/**
 * What a renewal costs.
 *
 * The member's own plan prices their renewal (`MembershipTerms.fee_plan_id`). When that plan has
 * been closed and replaced, `price_scope` on the replacement decides: ALL_MEMBERS moves them to
 * it, NEW_MEMBERS_ONLY leaves them on the closed plan's renewal price (fee-plans spec §7).
 */

export interface RenewalPlan {
  id: bigint;
  billing_cycle: BillingCycle;
  name: string;
  renewal_amount: Prisma.Decimal;
  tax_rate: Prisma.Decimal;
  currency: string;
  effective_from: Date;
  effective_to: Date | null;
  is_active: boolean;
  price_scope: PriceScope;
}

const PLAN_SELECT = {
  id: true,
  billing_cycle: true,
  name: true,
  renewal_amount: true,
  tax_rate: true,
  currency: true,
  effective_from: true,
  effective_to: true,
  is_active: true,
  price_scope: true,
} as const;

export const isLiveOn = (plan: RenewalPlan, day: Date): boolean =>
  plan.is_active &&
  plan.effective_from <= day &&
  (plan.effective_to === null || plan.effective_to >= day);

export const pickRenewalPlan = (
  own: RenewalPlan,
  liveSameCycle: RenewalPlan | null,
  day: Date,
): RenewalPlan => {
  if (isLiveOn(own, day)) return own;
  if (liveSameCycle && liveSameCycle.id !== own.id && liveSameCycle.price_scope === 'ALL_MEMBERS') {
    return liveSameCycle;
  }
  return own;
};

/** The same "live on a date" predicate the public plans page uses (`listPublicPlans`). */
const liveWhere = (day: Date) => ({
  deletedAt: null,
  is_active: true,
  structure: { is_active: true, deletedAt: null },
  effective_from: { lte: day },
  OR: [{ effective_to: null }, { effective_to: { gte: day } }],
});

export const loadRenewalPlan = async (
  db: Db,
  feePlanId: bigint,
  day: Date,
): Promise<RenewalPlan | null> => {
  const own = await db.feePlan.findFirst({ where: { id: feePlanId, deletedAt: null }, select: PLAN_SELECT });
  if (!own) return null;

  const live = await db.feePlan.findFirst({
    where: { ...liveWhere(day), billing_cycle: own.billing_cycle },
    orderBy: { effective_from: 'desc' },
    select: PLAN_SELECT,
  });

  return pickRenewalPlan(own, live, day);
};

/** A plan a member may switch to today: it must be on sale right now. */
export const loadLivePlan = (db: Db, feePlanId: bigint, day: Date): Promise<RenewalPlan | null> =>
  db.feePlan.findFirst({ where: { ...liveWhere(day), id: feePlanId }, select: PLAN_SELECT });

export const durationOf = (plan: RenewalPlan): number => CYCLE_MONTHS[plan.billing_cycle];

/** Whole-month pro-rata (decision 2026-08-21), tax per line rounded to 2 dp. */
export const priceRenewal = (
  amount: Prisma.Decimal,
  taxRate: Prisma.Decimal,
  window: Pick<TermWindow, 'months' | 'durationMonths' | 'prorated'>,
) => {
  const net = window.prorated
    ? amount.mul(window.months).div(window.durationMonths).toDecimalPlaces(2)
    : amount;
  const tax = net.mul(taxRate).div(100).toDecimalPlaces(2);

  return { net, tax, total: net.add(tax) };
};
```

- [ ] **Step 4: Run to verify it passes** — expected 6 passed.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 4: Pure state rules — reminder stage and term state

**Files:**
- Create: `backend/src/modules/renewal/renewal.state.ts`
- Test: `backend/src/modules/renewal/renewal.state.test.ts`

**Interfaces:**
- Produces:
  - `REMINDER_STAGES = [15, 7, 3, 0] as const`; `type ReminderCode = 'T-15' | 'T-7' | 'T-3' | 'T-0'`
  - `reminderStageFor(daysLeft: number): ReminderCode | null` — the smallest stage ≥ daysLeft; null when daysLeft < 0 or > 15. (Invoice raised late at 10 days → `T-15`; next day 9 → still `T-15`, already sent → nothing.)
  - `headlineFor(code: ReminderCode, expiresOn: string): string`
  - `type TermState = 'NONE' | 'INACTIVE' | 'AWAITING_FIRST_PAYMENT' | 'ACTIVE' | 'EXPIRING_SOON' | 'RENEWED' | 'IN_GRACE' | 'EXPIRED'`
  - `termState(i: { memberStatus: MemberStatus; current: { status: TermStatus; valid_till: Date } | null; renewalStatus: TermStatus | null; today: Date; noticeDays: number }): TermState`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { reminderStageFor, termState } from '@modules/renewal/renewal.state';

const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);
const base = { today: day('2027-03-20'), noticeDays: 15 };

describe('reminderStageFor', () => {
  it.each([
    [15, 'T-15'], [10, 'T-15'], [8, 'T-15'], [7, 'T-7'], [4, 'T-7'],
    [3, 'T-3'], [1, 'T-3'], [0, 'T-0'], [16, null], [-1, null],
  ])('%i days left → %s', (daysLeft, code) => {
    expect(reminderStageFor(daysLeft)).toBe(code);
  });
});

describe('termState', () => {
  const current = (till: string) => ({ status: 'ACTIVE' as const, valid_till: day(till) });

  it('is ACTIVE outside the notice window', () => {
    expect(termState({ ...base, memberStatus: 'ACTIVE', current: current('2027-09-11'), renewalStatus: null })).toBe('ACTIVE');
  });
  it('is EXPIRING_SOON inside the notice window', () => {
    expect(termState({ ...base, memberStatus: 'ACTIVE', current: current('2027-03-31'), renewalStatus: 'PENDING_PAYMENT' })).toBe('EXPIRING_SOON');
  });
  it('is RENEWED once the renewal is paid ahead', () => {
    expect(termState({ ...base, memberStatus: 'ACTIVE', current: current('2027-03-31'), renewalStatus: 'PAID_UPCOMING' })).toBe('RENEWED');
  });
  it('is IN_GRACE after the term ended while the member is still ACTIVE', () => {
    expect(termState({ ...base, memberStatus: 'ACTIVE', current: { status: 'EXPIRED', valid_till: day('2027-03-10') }, renewalStatus: 'PENDING_PAYMENT' })).toBe('IN_GRACE');
  });
  it('is EXPIRED when the member is EXPIRED', () => {
    expect(termState({ ...base, memberStatus: 'EXPIRED', current: { status: 'EXPIRED', valid_till: day('2027-01-31') }, renewalStatus: 'PENDING_PAYMENT' })).toBe('EXPIRED');
  });
  it('is AWAITING_FIRST_PAYMENT for an unpaid first term', () => {
    expect(termState({ ...base, memberStatus: 'PENDING', current: { status: 'PENDING_PAYMENT', valid_till: day('2028-03-19') }, renewalStatus: null })).toBe('AWAITING_FIRST_PAYMENT');
  });
  it('is INACTIVE for suspended or terminated members', () => {
    expect(termState({ ...base, memberStatus: 'SUSPENDED', current: current('2027-09-11'), renewalStatus: null })).toBe('INACTIVE');
  });
  it('is NONE with no term', () => {
    expect(termState({ ...base, memberStatus: 'DRAFT', current: null, renewalStatus: null })).toBe('NONE');
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/modules/renewal/renewal.state.test.ts` → FAIL.

- [ ] **Step 3: Implement**

```ts
import type { MemberStatus, TermStatus } from '@prisma/client';
import { daysBetween } from '@modules/renewal/renewal.dates';

/** Days before the current term ends at which a reminder is due (decided 2026-09-10). */
export const REMINDER_STAGES = [0, 3, 7, 15] as const;
export type ReminderCode = 'T-15' | 'T-7' | 'T-3' | 'T-0';

/**
 * The stage today falls in: the smallest stage at or above the days left. A stage missed
 * because the invoice was raised late is skipped, never sent in a burst — the member gets
 * today's message once, not three messages in one morning.
 */
export const reminderStageFor = (daysLeft: number): ReminderCode | null => {
  if (daysLeft < 0) return null;
  const stage = REMINDER_STAGES.find((s) => s >= daysLeft);
  return stage === undefined ? null : (`T-${stage}` as ReminderCode);
};

export const headlineFor = (code: ReminderCode, expiresOn: string): string => {
  switch (code) {
    case 'T-15':
      return `Your membership renews on ${expiresOn} — your renewal invoice is ready`;
    case 'T-7':
      return `7 days left — your membership ends on ${expiresOn}`;
    case 'T-3':
      return `3 days left — your membership ends on ${expiresOn}`;
    case 'T-0':
      return 'Your membership ends today';
  }
};

export type TermState =
  | 'NONE'
  | 'INACTIVE'
  | 'AWAITING_FIRST_PAYMENT'
  | 'ACTIVE'
  | 'EXPIRING_SOON'
  | 'RENEWED'
  | 'IN_GRACE'
  | 'EXPIRED';

/**
 * Where a member stands, decided once on the server so the banner, the membership page and any
 * later email all say the same thing (business logic belongs in the backend).
 */
export const termState = (input: {
  memberStatus: MemberStatus;
  current: { status: TermStatus; valid_till: Date } | null;
  renewalStatus: TermStatus | null;
  today: Date;
  noticeDays: number;
}): TermState => {
  const { memberStatus, current, renewalStatus, today, noticeDays } = input;

  if (memberStatus === 'SUSPENDED' || memberStatus === 'TERMINATED') return 'INACTIVE';
  if (!current) return 'NONE';
  if (current.status === 'PENDING_PAYMENT') return 'AWAITING_FIRST_PAYMENT';
  if (renewalStatus === 'PAID_UPCOMING') return 'RENEWED';
  if (memberStatus === 'EXPIRED') return 'EXPIRED';

  const daysLeft = daysBetween(today, current.valid_till);
  if (daysLeft < 0) return 'IN_GRACE';
  if (daysLeft <= noticeDays) return 'EXPIRING_SOON';
  return 'ACTIVE';
};
```

- [ ] **Step 4: Run to verify it passes** — expected 18 passed.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 5: `raiseRenewal` — one renewal term + one invoice

**Files:**
- Create: `backend/src/modules/renewal/renewal.raise.ts`
- Test: `backend/src/modules/renewal/renewal.raise.test.ts`

**Interfaces:**
- Consumes: Tasks 2–3; `allocateInvoiceNumber` from `@helpers/documentNumber`; `writeAudit` from `@helpers/audit`; `AUDIT_ACTIONS`, `ACTOR_TYPES` from `@constant/audit.constant`.
- Produces:
```ts
export interface RenewalSource {
  memberId: bigint; categoryId: bigint; tierId: bigint | null;
  feePlanId: bigint | null;       // the current term's plan
  previousValidTill: Date;         // UTC-midnight day the current term ends
}
export interface RaiseOptions {
  today: Date; basis: RenewalBasis; dueDays: number;
  /** Plan switch: price from this plan (already checked live) instead of resolving. */
  planOverride?: RenewalPlan;
}
export type RaiseResult =
  | { outcome: 'RAISED'; termId: bigint; invoiceId: bigint; invoiceNumber: string; total: string }
  | { outcome: 'SKIPPED'; reason: 'ALREADY_RAISED' | 'NO_PLAN' | 'NO_PRICE' };
export const raiseRenewal: (tx: Prisma.TransactionClient, src: RenewalSource, opts: RaiseOptions) => Promise<RaiseResult>;
```

Behaviour, in order (all inside the caller's transaction):
1. `SELECT pg_advisory_xact_lock(hashtext('membership.renewal'), (member_id % 2147483647)::int)` — serialises two runs for one member **before** an invoice number is taken (a rolled-back number would leave a gap in the GST invoice series).
2. `validFrom = addDays(previousValidTill, 1)`; if a non-CANCELLED term exists for `(member_id, valid_from)` → `SKIPPED/ALREADY_RAISED`.
3. Plan: `opts.planOverride ?? (feePlanId ? loadRenewalPlan(tx, feePlanId, validFrom) : null)`; null → `NO_PLAN`; `renewal_amount <= 0` → `NO_PRICE`. (Priced on `validFrom`: the price in force when the new term starts.)
4. `window = planRenewalTerm({ from: validFrom, durationMonths: durationOf(plan), basis })`; `price = priceRenewal(plan.renewal_amount, plan.tax_rate, window)`.
5. Create term `{ term_type: RENEWAL, status: PENDING_PAYMENT, valid_from, valid_till, fee_plan_id: plan.id, category_id, tier_id }`.
6. Create invoice `{ invoice_type: RENEWAL, status: ISSUED, issue_date: today, due_date: max(today + dueDays, today), amounts, one item }`, item description `` `${plan.name} renewal (${period})` `` with `period` = `12 months` or `1 month, pro-rata to 2027-03-31`; link `term.invoice_id`.
7. Audit `TERM_CREATED` and `INVOICE_ISSUED` with a SYSTEM actor — copy the exact `writeAudit` argument shape used for system writes in `src/modules/event/expiry.service.ts`.

- [ ] **Step 1: Write the failing test**

```ts
import { Prisma } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const D = (v: string) => new Prisma.Decimal(v);
const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);

const termFindFirst = vi.fn();
const termCreate = vi.fn();
const termUpdate = vi.fn();
const invoiceCreate = vi.fn();
const feePlanFindFirst = vi.fn();
const executeRaw = vi.fn();

const tx = {
  $executeRaw: executeRaw,
  membershipTerm: { findFirst: termFindFirst, create: termCreate, update: termUpdate },
  invoice: { create: invoiceCreate },
  feePlan: { findFirst: feePlanFindFirst },
};

vi.mock('@helpers/documentNumber', () => ({ allocateInvoiceNumber: vi.fn(async () => 'IN202701001') }));
vi.mock('@helpers/audit', () => ({ writeAudit: vi.fn(async () => undefined) }));

const { raiseRenewal } = await import('@modules/renewal/renewal.raise');

const QUARTERLY = {
  id: 7n, billing_cycle: 'QUARTERLY', name: 'Standard', renewal_amount: D('7000'), tax_rate: D('18'),
  currency: 'INR', effective_from: day('2026-04-01'), effective_to: null, is_active: true, price_scope: 'ALL_MEMBERS',
};

const SRC = { memberId: 5n, categoryId: 2n, tierId: null, feePlanId: 7n, previousValidTill: day('2027-03-11') };
const OPTS = { today: day('2027-02-24'), basis: 'financial_year' as const, dueDays: 15 };

describe('raiseRenewal', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    termFindFirst.mockResolvedValue(null);
    feePlanFindFirst.mockResolvedValue(QUARTERLY);
    termCreate.mockResolvedValue({ id: 99n });
    invoiceCreate.mockResolvedValue({ id: 500n, invoice_number: 'IN202701001' });
  });

  it('skips when a live term already starts the day after', async () => {
    termFindFirst.mockResolvedValue({ id: 1n });
    await expect(raiseRenewal(tx as never, SRC, OPTS)).resolves.toEqual({ outcome: 'SKIPPED', reason: 'ALREADY_RAISED' });
    expect(invoiceCreate).not.toHaveBeenCalled();
  });

  it('skips a term with no plan', async () => {
    await expect(raiseRenewal(tx as never, { ...SRC, feePlanId: null }, OPTS)).resolves.toEqual({ outcome: 'SKIPPED', reason: 'NO_PLAN' });
  });

  it('never raises a zero invoice', async () => {
    feePlanFindFirst.mockResolvedValue({ ...QUARTERLY, renewal_amount: D('0') });
    await expect(raiseRenewal(tx as never, SRC, OPTS)).resolves.toEqual({ outcome: 'SKIPPED', reason: 'NO_PRICE' });
    expect(termCreate).not.toHaveBeenCalled();
  });

  it('raises a contiguous, prorated term under financial_year', async () => {
    const result = await raiseRenewal(tx as never, SRC, OPTS);

    expect(result).toMatchObject({ outcome: 'RAISED', termId: 99n, invoiceId: 500n, total: '2753.33' });
    const term = termCreate.mock.calls[0][0].data;
    expect(term).toMatchObject({ term_type: 'RENEWAL', status: 'PENDING_PAYMENT', fee_plan_id: 7n });
    expect(term.valid_from.toISOString().slice(0, 10)).toBe('2027-03-12');
    expect(term.valid_till.toISOString().slice(0, 10)).toBe('2027-03-31');
    const invoice = invoiceCreate.mock.calls[0][0].data;
    expect(invoice).toMatchObject({ invoice_type: 'RENEWAL', status: 'ISSUED' });
    expect(invoice.total_amount.toFixed(2)).toBe('2753.33');
    expect(termUpdate).toHaveBeenCalledWith({ where: { id: 99n }, data: { invoice_id: 500n } });
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/modules/renewal/renewal.raise.test.ts` → FAIL.

- [ ] **Step 3: Implement**

```ts
import { InvoiceStatus, InvoiceType, Prisma, TermStatus, TermType } from '@prisma/client';
import { ACTOR_TYPES, AUDIT_ACTIONS } from '@constant/audit.constant';
import { writeAudit } from '@helpers/audit';
import { allocateInvoiceNumber } from '@helpers/documentNumber';
import type { RenewalBasis } from '@helpers/settings';
import { addDays, isoDay, planRenewalTerm } from '@modules/renewal/renewal.dates';
import {
  durationOf,
  loadRenewalPlan,
  priceRenewal,
  type RenewalPlan,
} from '@modules/renewal/renewal.pricing';

export interface RenewalSource {
  memberId: bigint;
  categoryId: bigint;
  tierId: bigint | null;
  feePlanId: bigint | null;
  previousValidTill: Date;
}

export interface RaiseOptions {
  today: Date;
  basis: RenewalBasis;
  dueDays: number;
  planOverride?: RenewalPlan;
}

export type RaiseResult =
  | { outcome: 'RAISED'; termId: bigint; invoiceId: bigint; invoiceNumber: string; total: string }
  | { outcome: 'SKIPPED'; reason: 'ALREADY_RAISED' | 'NO_PLAN' | 'NO_PRICE' };

/**
 * Raise one member's next term and the invoice that pays for it.
 *
 * Runs in the caller's transaction: the term and its invoice are one fact, and a crash between
 * them would leave a member billed for nothing or covered for free.
 */
export const raiseRenewal = async (
  tx: Prisma.TransactionClient,
  src: RenewalSource,
  opts: RaiseOptions,
): Promise<RaiseResult> => {
  // Before any invoice number is taken: a number allocated in a transaction that then rolls back
  // is a gap in the invoice series. The unique index is the backstop, this is the courtesy.
  // $executeRaw, not $queryRaw: the function returns void, which Prisma cannot deserialise.
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext('membership.renewal'), (${src.memberId} % 2147483647)::int)`;

  const validFrom = addDays(src.previousValidTill, 1);

  const existing = await tx.membershipTerm.findFirst({
    where: { member_id: src.memberId, valid_from: validFrom, status: { not: TermStatus.CANCELLED } },
    select: { id: true },
  });
  if (existing) return { outcome: 'SKIPPED', reason: 'ALREADY_RAISED' };

  const plan =
    opts.planOverride ?? (src.feePlanId ? await loadRenewalPlan(tx, src.feePlanId, validFrom) : null);
  if (!plan) return { outcome: 'SKIPPED', reason: 'NO_PLAN' };
  // A ₹0 invoice raised because nobody priced renewal is far worse than a job that refused.
  if (plan.renewal_amount.lte(0)) return { outcome: 'SKIPPED', reason: 'NO_PRICE' };

  const window = planRenewalTerm({ from: validFrom, durationMonths: durationOf(plan), basis: opts.basis });
  const price = priceRenewal(plan.renewal_amount, plan.tax_rate, window);

  const term = await tx.membershipTerm.create({
    data: {
      member_id: src.memberId,
      category_id: src.categoryId,
      tier_id: src.tierId,
      term_type: TermType.RENEWAL,
      valid_from: window.validFrom,
      valid_till: window.validTill,
      status: TermStatus.PENDING_PAYMENT,
      fee_plan_id: plan.id,
    },
  });

  const dueDate = addDays(opts.today, Math.max(opts.dueDays, 0));
  const months = `${window.months} month${window.months === 1 ? '' : 's'}`;
  const period = window.prorated ? `${months}, pro-rata to ${isoDay(window.validTill)}` : months;

  const invoice = await tx.invoice.create({
    data: {
      invoice_number: await allocateInvoiceNumber(tx, opts.today),
      member_id: src.memberId,
      invoice_type: InvoiceType.RENEWAL,
      status: InvoiceStatus.ISSUED,
      issue_date: opts.today,
      due_date: dueDate,
      subtotal: price.net,
      tax_amount: price.tax,
      total_amount: price.total,
      amount_paid: new Prisma.Decimal(0),
      balance_due: price.total,
      currency: plan.currency,
      items: {
        create: [
          {
            description: `${plan.name} renewal (${period})`,
            quantity: new Prisma.Decimal(1),
            unit_price: price.net,
            tax_rate: plan.tax_rate,
            tax_amount: price.tax,
            line_total: price.total,
            fee_structure_id: null,
            fee_plan_id: plan.id,
            sort_order: 0,
          },
        ],
      },
    },
  });

  await tx.membershipTerm.update({ where: { id: term.id }, data: { invoice_id: invoice.id } });

  // Copy the SYSTEM-actor shape from event/expiry.service.ts verbatim for the remaining fields.
  const system = { actorType: ACTOR_TYPES.SYSTEM, actorId: null, ip: null, userAgent: null, requestId: null };
  await writeAudit(tx, {
    ...system,
    action: AUDIT_ACTIONS.TERM_CREATED,
    entityName: 'MembershipTerms',
    entityId: term.id,
    before: null,
    after: { term_type: 'RENEWAL', valid_from: isoDay(window.validFrom), valid_till: isoDay(window.validTill) },
  });
  await writeAudit(tx, {
    ...system,
    action: AUDIT_ACTIONS.INVOICE_ISSUED,
    entityName: 'Invoices',
    entityId: invoice.id,
    before: null,
    after: { invoice_type: 'RENEWAL', total_amount: price.total.toFixed(2) },
  });

  return {
    outcome: 'RAISED',
    termId: term.id,
    invoiceId: invoice.id,
    invoiceNumber: invoice.invoice_number,
    total: price.total.toFixed(2),
  };
};
```
If `writeAudit`'s input type rejects `requestId: null` or `userAgent: null`, match whatever `expiry.service.ts` passes — do not widen the helper's type.

- [ ] **Step 4: Run to verify it passes** — expected 4 passed; then `npm run typecheck`.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 6: Payment hook — `PAID_UPCOMING`, renew-from-expired, current term

**Files:**
- Modify: `backend/src/modules/billing/membershipActivation.ts` (whole function, :22–63)
- Modify test: `backend/src/modules/billing/membershipActivation.test.ts`

**Interfaces:**
- Consumes: `dbToday` (Task 2).
- Produces: `activateMembershipForInvoice(tx, { invoiceId, memberId, invoiceNumber, changedByAdminId, today? })` — same callers (`member.service.ts:731`, `event/payment.service.ts:284`), no call-site changes.

New behaviour:
- Terms on the invoice still `PENDING_PAYMENT` with `valid_from > today` → `PAID_UPCOMING` (member untouched).
- Terms with `valid_from <= today`, oldest first: any *other* `ACTIVE` term of the member → `EXPIRED`; this term → `ACTIVE`; `Members.current_term_id` → this term.
- Member `PENDING` → `ACTIVE` (+ `joined_on`) as before. Member `EXPIRED` → `ACTIVE` **only if a term went ACTIVE now**, reason `Renewal invoice ${n} paid`.

- [ ] **Step 1: Replace the test file's cases** — keep the existing mock header (imports, `vi.mock('@modules/member/member.repository', …)`); change `tx` and the cases to:

```ts
const termFindMany = vi.fn();
const termUpdateMany = vi.fn();
const termUpdate = vi.fn();
const memberUpdate = vi.fn();
const tx = {
  membershipTerm: { findMany: termFindMany, updateMany: termUpdateMany, update: termUpdate },
  member: { update: memberUpdate },
};
const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);
const TODAY = day('2027-03-20');
const run = () => activateMembershipForInvoice(tx as any, { ...PARAMS, today: TODAY });

describe('activateMembershipForInvoice', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    findMemberById.mockResolvedValue({ id: 5n, status: 'PENDING', joined_on: null });
    updateMember.mockResolvedValue({ id: 5n, status: 'ACTIVE' });
  });

  it('activates a first term that has started and points the member at it', async () => {
    termFindMany.mockResolvedValue([{ id: 11n, valid_from: day('2027-03-01') }]);
    await run();
    expect(termUpdate).toHaveBeenCalledWith({ where: { id: 11n }, data: { status: 'ACTIVE' } });
    expect(memberUpdate).toHaveBeenCalledWith({ where: { id: 5n }, data: { current_term_id: 11n } });
    expect(updateMember).toHaveBeenCalledWith(tx, 5n, expect.objectContaining({ status: 'ACTIVE' }));
  });

  it('holds an early renewal payment as PAID_UPCOMING and leaves the member alone', async () => {
    findMemberById.mockResolvedValue({ id: 5n, status: 'ACTIVE', joined_on: day('2026-04-01') });
    termFindMany.mockResolvedValue([{ id: 12n, valid_from: day('2027-04-01') }]);
    await run();
    expect(termUpdateMany).toHaveBeenCalledWith({ where: { id: { in: [12n] } }, data: { status: 'PAID_UPCOMING' } });
    expect(termUpdate).not.toHaveBeenCalled();
    expect(updateMember).not.toHaveBeenCalled();
  });

  it('closes the ended term before activating a renewal paid in grace', async () => {
    findMemberById.mockResolvedValue({ id: 5n, status: 'ACTIVE', joined_on: day('2026-04-01') });
    termFindMany.mockResolvedValue([{ id: 12n, valid_from: day('2027-03-12') }]);
    await run();
    expect(termUpdateMany).toHaveBeenCalledWith({
      where: { member_id: 5n, status: 'ACTIVE', id: { not: 12n } }, data: { status: 'EXPIRED' },
    });
    expect(termUpdate).toHaveBeenCalledWith({ where: { id: 12n }, data: { status: 'ACTIVE' } });
    expect(updateMember).not.toHaveBeenCalled();
  });

  it('brings an EXPIRED member back when their renewal is paid', async () => {
    findMemberById.mockResolvedValue({ id: 5n, status: 'EXPIRED', joined_on: day('2026-04-01') });
    termFindMany.mockResolvedValue([{ id: 12n, valid_from: day('2027-02-01') }]);
    await run();
    expect(updateMember).toHaveBeenCalledWith(tx, 5n, { status: 'ACTIVE' });
    expect(recordStatusChange).toHaveBeenCalledWith(tx, expect.objectContaining({
      from_status: 'EXPIRED', to_status: 'ACTIVE', reason: 'Renewal invoice IN202603001 paid',
    }));
  });

  it('does nothing to the member for an invoice with no pending term (event invoice)', async () => {
    findMemberById.mockResolvedValue({ id: 5n, status: 'EXPIRED', joined_on: day('2026-04-01') });
    termFindMany.mockResolvedValue([]);
    await run();
    expect(updateMember).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/modules/billing/membershipActivation.test.ts` → FAIL.

- [ ] **Step 3: Implement** — replace the body of `activateMembershipForInvoice` (keep the header comment, extend it with the M6 paragraph below):

```ts
import { MemberStatus, TermStatus } from '@prisma/client';

import * as repo from '@modules/member/member.repository';
import { dbToday } from '@modules/renewal/renewal.dates';
import type { Db } from '@db/prisma';

/* …existing header comment…
 *
 * M6: a renewal can be paid before its term starts. The database allows one ACTIVE term per
 * member and the current one is still running, so such a term waits as PAID_UPCOMING and the
 * renewal job starts it on its first day. A renewal paid on or after its first day starts now,
 * closing the ended term first — and brings back a member the sweep had already expired.
 */
export const activateMembershipForInvoice = async (
  tx: Db,
  params: {
    invoiceId: bigint;
    memberId: bigint;
    invoiceNumber: string;
    changedByAdminId: bigint | null;
    /** Injected by tests; defaults to the server's local calendar day. */
    today?: Date;
  },
) => {
  const today = params.today ?? dbToday();

  const pending = await tx.membershipTerm.findMany({
    where: { invoice_id: params.invoiceId, status: TermStatus.PENDING_PAYMENT },
    select: { id: true, valid_from: true },
    orderBy: { valid_from: 'asc' },
  });

  const later = pending.filter((t) => t.valid_from > today);
  const now = pending.filter((t) => t.valid_from <= today);

  if (later.length > 0) {
    await tx.membershipTerm.updateMany({
      where: { id: { in: later.map((t) => t.id) } },
      data: { status: TermStatus.PAID_UPCOMING },
    });
  }

  let activated: bigint | null = null;
  for (const term of now) {
    // One ACTIVE term per member (MembershipTerms_one_active_per_member): the ended one steps
    // aside first, in the same transaction.
    await tx.membershipTerm.updateMany({
      where: { member_id: params.memberId, status: TermStatus.ACTIVE, id: { not: term.id } },
      data: { status: TermStatus.EXPIRED },
    });
    await tx.membershipTerm.update({ where: { id: term.id }, data: { status: TermStatus.ACTIVE } });
    activated = term.id;
  }

  if (activated !== null) {
    await tx.member.update({ where: { id: params.memberId }, data: { current_term_id: activated } });
  }

  const member = await repo.findMemberById(tx, params.memberId);
  if (!member) return member;

  if (member.status === MemberStatus.PENDING) {
    const updated = await repo.updateMember(tx, params.memberId, {
      status: MemberStatus.ACTIVE,
      ...(member.joined_on ? {} : { joined_on: new Date() }),
    });
    await repo.recordStatusChange(tx, {
      member_id: params.memberId,
      from_status: member.status,
      to_status: MemberStatus.ACTIVE,
      reason: `Invoice ${params.invoiceNumber} paid`,
      changed_by_admin_id: params.changedByAdminId,
    });
    return updated;
  }

  // Only a term that started now brings an expired member back; paying ahead does not.
  if (member.status === MemberStatus.EXPIRED && activated !== null) {
    const updated = await repo.updateMember(tx, params.memberId, { status: MemberStatus.ACTIVE });
    await repo.recordStatusChange(tx, {
      member_id: params.memberId,
      from_status: member.status,
      to_status: MemberStatus.ACTIVE,
      reason: `Renewal invoice ${params.invoiceNumber} paid`,
      changed_by_admin_id: params.changedByAdminId,
    });
    return updated;
  }

  return member;
};
```

- [ ] **Step 4: Run** — `npx vitest run src/modules/billing src/modules/member src/modules/event` → all PASS. `member.invoicePayment.test.ts` and the payment-verify tests mock `tx.membershipTerm.updateMany`; add `findMany: vi.fn(async () => [])`, `update: vi.fn()` to their `tx.membershipTerm` and `member: { update: vi.fn() }` to their `tx` if they fail on a missing method — do not change their assertions.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 7: Lifecycle steps and the hourly job

**Files:**
- Create: `backend/src/modules/renewal/renewal.repository.ts`
- Create: `backend/src/modules/renewal/renewal.notify.ts`
- Create: `backend/src/modules/renewal/renewal.lifecycle.ts`
- Test: `backend/src/modules/renewal/renewal.lifecycle.test.ts`
- Modify: `backend/src/jobs/definitions.ts` (add `renewalJob`, register in `jobDefinitions`)

**Interfaces:**
- Consumes: Tasks 2–5; `getSetting`, `getNumericSetting`, `SETTING_KEYS`; `queueNotifications` from `@notifications/outbox`; `repo.recordStatusChange` from `@modules/member/member.repository`.
- Produces:
```ts
export interface CycleSummary {
  closed: number; started: number; expired: number;
  raised: number; skipped: { member_code: string | null; company_name: string; reason: string }[];
  reminded: number;
}
export const runRenewalCycle: (now?: Date) => Promise<CycleSummary>;
export const closeEndedTerms: (today: Date) => Promise<number>;
export const startPaidTerms: (today: Date) => Promise<number>;
export const expireLapsedMembers: (today: Date, graceDays: number) => Promise<number>;
export const raiseDueRenewals: (today: Date, cfg: { noticeDays: number; basis: RenewalBasis; dueDays: number }) => Promise<Pick<CycleSummary, 'raised' | 'skipped'>>;
export const sendRenewalReminders: (today: Date) => Promise<number>;
```

Order inside `runRenewalCycle` (each step idempotent, each member in its own transaction, one failure is logged and skipped):
1. `closeEndedTerms` — `ACTIVE` terms with `valid_till < today` → `EXPIRED` (member stays `ACTIVE` = grace).
2. `startPaidTerms` — `PAID_UPCOMING` with `valid_from <= today`: close the member's other `ACTIVE` term, set this `ACTIVE`, move `current_term_id`.
3. `expireLapsedMembers` — members `ACTIVE` whose `current_term` is `EXPIRED` with `valid_till < today − graceDays` → member `EXPIRED`, status history (system), `membership.expired` message.
4. `raiseDueRenewals` — candidates from the repository; `raiseRenewal` per member; P2002 (unique violation) → `ALREADY_RAISED`.
5. `sendRenewalReminders` — pending renewal invoices; stage = `reminderStageFor(daysLeft)`; insert reminder row `ON CONFLICT DO NOTHING`; queue message only if a row was inserted; skip invoices with a `PENDING` payment submission (the member has told us they paid).

- [ ] **Step 1: Repository**

```ts
import { Prisma } from '@prisma/client';
import type { Db } from '@db/prisma';

export interface DueCandidate {
  term_id: bigint;
  member_id: bigint;
  category_id: bigint;
  tier_id: bigint | null;
  fee_plan_id: bigint | null;
  valid_till: Date;
  member_code: string | null;
  company_name: string;
}

/**
 * Members whose current term ends within the notice window (or has ended — a member in grace
 * whose invoice was never raised is still owed one) and who have no live next term yet.
 */
export const dueCandidates = (db: Db, horizon: Date) =>
  db.$queryRaw<DueCandidate[]>(Prisma.sql`
    SELECT t.id AS term_id, t.member_id, t.category_id, t.tier_id, t.fee_plan_id, t.valid_till,
           m.member_code, m.company_name
    FROM "Members" m
    JOIN "MembershipTerms" t ON t.id = m.current_term_id
    WHERE m.status = 'ACTIVE' AND m."deletedAt" IS NULL
      AND t.status IN ('ACTIVE', 'EXPIRED')
      AND t.valid_till <= ${isoDay(horizon)}::date
      AND NOT EXISTS (
        SELECT 1 FROM "MembershipTerms" n
        WHERE n.member_id = t.member_id
          AND n.valid_from = t.valid_till + 1
          AND n.status <> 'CANCELLED')
    ORDER BY t.valid_till, t.member_id
  `);

export interface ReminderCandidate {
  term_id: bigint;
  member_id: bigint;
  valid_from: Date;
  invoice_number: string;
  total_amount: Prisma.Decimal;
  currency: string;
  due_date: Date;
  plan_name: string | null;
}

/** Unpaid renewal invoices whose current term ends today or within 15 days, no claim filed. */
export const reminderCandidates = (db: Db, today: Date) =>
  db.$queryRaw<ReminderCandidate[]>(Prisma.sql`
    SELECT n.id AS term_id, n.member_id, n.valid_from, i.invoice_number, i.total_amount,
           i.currency, i.due_date, p.name AS plan_name
    FROM "MembershipTerms" n
    JOIN "Invoices" i ON i.id = n.invoice_id AND i."deletedAt" IS NULL
    LEFT JOIN "FeePlans" p ON p.id = n.fee_plan_id
    WHERE n.term_type = 'RENEWAL' AND n.status = 'PENDING_PAYMENT'
      AND i.status IN ('ISSUED', 'PARTIALLY_PAID', 'OVERDUE')
      AND n.valid_from - 1 BETWEEN ${isoDay(today)}::date AND ${isoDay(today)}::date + 15
      AND NOT EXISTS (
        SELECT 1 FROM "PaymentSubmissions" s
        WHERE s.invoice_id = i.id AND s.status = ${SUBMISSION_STATUS.PENDING})
  `);

/** Inserts the reminder row; returns 1 when inserted, 0 when this stage was already sent. */
export const claimReminder = (db: Db, termId: bigint, code: string, today: Date) =>
  db.$executeRaw(Prisma.sql`
    INSERT INTO "RenewalReminders" ("term_id", "reminder_code", "sent_on")
    VALUES (${termId}, ${code}, ${isoDay(today)}::date)
    ON CONFLICT ("term_id", "reminder_code") DO NOTHING
  `);
```
Before relying on it, confirm the table/column names `PaymentSubmissions.invoice_id` and `.status` in `prisma/schema/*.prisma`. The status is a smallint code: use `SUBMISSION_STATUS.PENDING` from `src/modules/event/registration.constants.ts`, as `paymentClaim.service.ts` does — the string `'PENDING'` matches nothing and would silently disable the claim-pending guard.

- [ ] **Step 2: Notify helper**

```ts
import { NotificationChannel } from '@prisma/client';
import type { Db } from '@db/prisma';
import { queueNotifications } from '@notifications/outbox';

/**
 * Renewal messages go to the company's primary login, on email and in-app. No address means no
 * message — the renewal itself still happens (same rule as membershipNotify.send).
 * Mirror the queueNotifications argument shape used for `application.approved` in
 * activation.service.ts if a field below differs.
 */
export const notifyMember = async (
  db: Db,
  memberId: bigint,
  templateCode: 'membership.renewal_reminder' | 'membership.expired',
  payload: Record<string, string>,
): Promise<number> => {
  const member = await db.member.findFirst({
    where: { id: memberId },
    select: { company_name: true, primary_user: { select: { id: true, email: true } } },
  });
  if (!member?.primary_user?.email) return 0;

  await queueNotifications(db, [NotificationChannel.EMAIL, NotificationChannel.IN_APP], {
    templateCode,
    memberId,
    userId: member.primary_user.id,
    toAddress: member.primary_user.email,
    payload: { name: member.company_name, ...payload },
  });
  return 1;
};
```

- [ ] **Step 3: Write the failing lifecycle test** (orchestration only; SQL is covered by the Sentinel suite in Task 15)

```ts
import { Prisma } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);

const dueCandidates = vi.fn();
const reminderCandidates = vi.fn();
const claimReminder = vi.fn();
const raiseRenewal = vi.fn();
const notifyMember = vi.fn();

vi.mock('@modules/renewal/renewal.repository', () => ({
  dueCandidates: (...a: unknown[]) => dueCandidates(...a),
  reminderCandidates: (...a: unknown[]) => reminderCandidates(...a),
  claimReminder: (...a: unknown[]) => claimReminder(...a),
}));
vi.mock('@modules/renewal/renewal.raise', () => ({ raiseRenewal: (...a: unknown[]) => raiseRenewal(...a) }));
vi.mock('@modules/renewal/renewal.notify', () => ({ notifyMember: (...a: unknown[]) => notifyMember(...a) }));
vi.mock('@db/prisma', () => ({ prisma: { $transaction: (fn: (tx: unknown) => unknown) => fn({}) } }));

const { raiseDueRenewals, sendRenewalReminders } = await import('@modules/renewal/renewal.lifecycle');

const CFG = { noticeDays: 15, basis: 'term' as const, dueDays: 15 };
const cand = (over = {}) => ({
  term_id: 1n, member_id: 5n, category_id: 2n, tier_id: null, fee_plan_id: 7n,
  valid_till: day('2027-09-11'), member_code: 'LGDGF/2026/0042', company_name: 'Sunrise Foods', ...over,
});

describe('raiseDueRenewals', () => {
  beforeEach(() => vi.clearAllMocks());

  it('raises each candidate and reports skips by company', async () => {
    dueCandidates.mockResolvedValue([cand(), cand({ member_id: 6n, company_name: 'Shreeji Exports', fee_plan_id: null })]);
    raiseRenewal
      .mockResolvedValueOnce({ outcome: 'RAISED', termId: 9n, invoiceId: 10n, invoiceNumber: 'IN1', total: '23600.00' })
      .mockResolvedValueOnce({ outcome: 'SKIPPED', reason: 'NO_PLAN' });

    const result = await raiseDueRenewals(day('2027-08-27'), CFG);

    expect(dueCandidates).toHaveBeenCalledWith(expect.anything(), day('2027-09-11'));
    expect(result.raised).toBe(1);
    expect(result.skipped).toEqual([{ member_code: 'LGDGF/2026/0042', company_name: 'Shreeji Exports', reason: 'NO_PLAN' }]);
  });

  it('treats a unique-violation race as already raised, not a failure', async () => {
    dueCandidates.mockResolvedValue([cand()]);
    raiseRenewal.mockRejectedValue(new Prisma.PrismaClientKnownRequestError('dup', { code: 'P2002', clientVersion: 'x' }));
    const result = await raiseDueRenewals(day('2027-08-27'), CFG);
    expect(result.raised).toBe(0);
    expect(result.skipped[0].reason).toBe('ALREADY_RAISED');
  });
});

describe('sendRenewalReminders', () => {
  beforeEach(() => vi.clearAllMocks());

  const rem = (validFrom: string) => ({
    term_id: 9n, member_id: 5n, valid_from: day(validFrom), invoice_number: 'IN1',
    total_amount: new Prisma.Decimal('23600'), currency: 'INR', due_date: day('2027-09-11'), plan_name: 'Best Value',
  });

  it('sends the stage for today once', async () => {
    reminderCandidates.mockResolvedValue([rem('2027-09-12')]); // ends 11 Sep, today 4 Sep → 7 days
    claimReminder.mockResolvedValue(1);
    notifyMember.mockResolvedValue(1);
    await expect(sendRenewalReminders(day('2027-09-04'))).resolves.toBe(1);
    expect(claimReminder).toHaveBeenCalledWith(expect.anything(), 9n, 'T-7', day('2027-09-04'));
    expect(notifyMember).toHaveBeenCalledWith(expect.anything(), 5n, 'membership.renewal_reminder',
      expect.objectContaining({ invoice_number: 'IN1', expires_on: '2027-09-11' }));
  });

  it('sends nothing when the stage was already sent', async () => {
    reminderCandidates.mockResolvedValue([rem('2027-09-12')]);
    claimReminder.mockResolvedValue(0);
    await expect(sendRenewalReminders(day('2027-09-04'))).resolves.toBe(0);
    expect(notifyMember).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 4: Run to verify it fails** — `npx vitest run src/modules/renewal/renewal.lifecycle.test.ts` → FAIL.

- [ ] **Step 5: Implement `renewal.lifecycle.ts`**

```ts
import { MemberStatus, Prisma, TermStatus } from '@prisma/client';
import { prisma } from '@db/prisma';
import { logger } from '@logger/logger';
import { getNumericSetting, getSetting, SETTING_KEYS, type RenewalBasis } from '@helpers/settings';
import * as memberRepo from '@modules/member/member.repository';
import { addDays, daysBetween, dbToday, isoDay } from '@modules/renewal/renewal.dates';
import { notifyMember } from '@modules/renewal/renewal.notify';
import { raiseRenewal } from '@modules/renewal/renewal.raise';
import * as repo from '@modules/renewal/renewal.repository';
import { headlineFor, reminderStageFor } from '@modules/renewal/renewal.state';

export interface CycleSummary {
  closed: number;
  started: number;
  expired: number;
  raised: number;
  skipped: { member_code: string | null; company_name: string; reason: string }[];
  reminded: number;
}

const isUniqueViolation = (error: unknown) =>
  error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002';

/** A term past its last day is over. The member keeps ACTIVE status through grace. */
export const closeEndedTerms = async (today: Date): Promise<number> => {
  const result = await prisma.membershipTerm.updateMany({
    where: { status: TermStatus.ACTIVE, valid_till: { lt: today } },
    data: { status: TermStatus.EXPIRED },
  });
  return result.count;
};

/** Renewals paid ahead start on their first day. */
export const startPaidTerms = async (today: Date): Promise<number> => {
  const due = await prisma.membershipTerm.findMany({
    where: { status: TermStatus.PAID_UPCOMING, valid_from: { lte: today } },
    select: { id: true, member_id: true },
    orderBy: { valid_from: 'asc' },
  });

  let started = 0;
  for (const term of due) {
    try {
      await prisma.$transaction(async (tx) => {
        await tx.membershipTerm.updateMany({
          where: { member_id: term.member_id, status: TermStatus.ACTIVE, id: { not: term.id } },
          data: { status: TermStatus.EXPIRED },
        });
        await tx.membershipTerm.update({ where: { id: term.id }, data: { status: TermStatus.ACTIVE } });
        await tx.member.update({ where: { id: term.member_id }, data: { current_term_id: term.id } });
      });
      started += 1;
    } catch (error) {
      logger.error('renewal.startPaidTerm.failed', { termId: term.id.toString(), detail: String(error) });
    }
  }
  return started;
};

/** Grace is over: the member leaves the directory and member pricing, keeps their login. */
export const expireLapsedMembers = async (today: Date, graceDays: number): Promise<number> => {
  const cutoff = addDays(today, -graceDays);
  const lapsed = await prisma.member.findMany({
    where: {
      status: MemberStatus.ACTIVE,
      deletedAt: null,
      current_term: { status: TermStatus.EXPIRED, valid_till: { lt: cutoff } },
    },
    select: { id: true, current_term: { select: { valid_till: true } } },
  });

  let expired = 0;
  for (const member of lapsed) {
    const endedOn = isoDay(member.current_term!.valid_till);
    try {
      await prisma.$transaction(async (tx) => {
        await memberRepo.updateMember(tx, member.id, { status: MemberStatus.EXPIRED });
        await memberRepo.recordStatusChange(tx, {
          member_id: member.id,
          from_status: MemberStatus.ACTIVE,
          to_status: MemberStatus.EXPIRED,
          reason: `Membership ended ${endedOn}; the ${graceDays}-day grace period passed without renewal`,
          changed_by_admin_id: null,
        });
        await notifyMember(tx, member.id, 'membership.expired', { expired_on: endedOn });
      });
      expired += 1;
    } catch (error) {
      logger.error('renewal.expire.failed', { memberId: member.id.toString(), detail: String(error) });
    }
  }
  return expired;
};

export const raiseDueRenewals = async (
  today: Date,
  cfg: { noticeDays: number; basis: RenewalBasis; dueDays: number },
): Promise<Pick<CycleSummary, 'raised' | 'skipped'>> => {
  const candidates = await repo.dueCandidates(prisma, addDays(today, cfg.noticeDays));
  const summary: Pick<CycleSummary, 'raised' | 'skipped'> = { raised: 0, skipped: [] };

  for (const c of candidates) {
    const who = { member_code: c.member_code, company_name: c.company_name };
    try {
      const result = await prisma.$transaction((tx) =>
        raiseRenewal(
          tx,
          {
            memberId: c.member_id,
            categoryId: c.category_id,
            tierId: c.tier_id,
            feePlanId: c.fee_plan_id,
            previousValidTill: c.valid_till,
          },
          { today, basis: cfg.basis, dueDays: cfg.dueDays },
        ),
      );
      if (result.outcome === 'RAISED') summary.raised += 1;
      else summary.skipped.push({ ...who, reason: result.reason });
    } catch (error) {
      if (isUniqueViolation(error)) {
        summary.skipped.push({ ...who, reason: 'ALREADY_RAISED' });
      } else {
        summary.skipped.push({ ...who, reason: 'FAILED' });
        logger.error('renewal.raise.failed', { memberId: c.member_id.toString(), detail: String(error) });
      }
    }
  }
  return summary;
};

export const sendRenewalReminders = async (today: Date): Promise<number> => {
  const rows = await repo.reminderCandidates(prisma, today);
  let sent = 0;

  for (const row of rows) {
    const expiresOn = addDays(row.valid_from, -1);
    const code = reminderStageFor(daysBetween(today, expiresOn));
    if (!code) continue;

    try {
      await prisma.$transaction(async (tx) => {
        const inserted = await repo.claimReminder(tx, row.term_id, code, today);
        if (inserted === 0) return;
        sent += await notifyMember(tx, row.member_id, 'membership.renewal_reminder', {
          headline: headlineFor(code, isoDay(expiresOn)),
          plan_name: row.plan_name ?? 'Membership',
          amount: `${row.currency} ${row.total_amount.toFixed(2)}`,
          invoice_number: row.invoice_number,
          expires_on: isoDay(expiresOn),
          due_on: isoDay(row.due_date),
        });
      });
    } catch (error) {
      logger.error('renewal.remind.failed', { termId: row.term_id.toString(), detail: String(error) });
    }
  }
  return sent;
};

/**
 * One pass of the renewal machinery. Order matters: ended terms close before paid ones start
 * (one ACTIVE term per member), and members expire before anything is billed. Every step is
 * safe to run twice — the hourly schedule and the admin's "Generate Invoices" both call this.
 */
export const runRenewalCycle = async (now: Date = new Date()): Promise<CycleSummary> => {
  const today = dbToday(now);
  const basis = ((await getSetting(SETTING_KEYS.RENEWAL_BASIS)) ?? 'term') as RenewalBasis;
  const noticeDays = await getNumericSetting(SETTING_KEYS.RENEWAL_NOTICE_DAYS, 15);
  const graceDays = await getNumericSetting(SETTING_KEYS.MEMBERSHIP_GRACE_DAYS, 30);
  const dueDays = await getNumericSetting(SETTING_KEYS.INVOICE_DUE_DAYS, 15);

  const closed = await closeEndedTerms(today);
  const started = await startPaidTerms(today);
  const expired = await expireLapsedMembers(today, graceDays);
  const { raised, skipped } = await raiseDueRenewals(today, { noticeDays, basis, dueDays });
  const reminded = await sendRenewalReminders(today);

  return { closed, started, expired, raised, skipped, reminded };
};
```
Note: `sent += await …` inside the transaction callback counts a message whose transaction later rolls back; acceptable for a log count. `memberRepo.updateMember` / `recordStatusChange` signatures are the ones `membershipActivation.ts` already uses.

- [ ] **Step 6: Run to verify it passes** — expected 4 passed.

- [ ] **Step 7: Register the job** — in `src/jobs/definitions.ts`:
```ts
import { runRenewalCycle } from '@modules/renewal/renewal.lifecycle';

/**
 * Membership renewal (M6).
 *
 * Hourly, not nightly: every step is idempotent (DB-enforced), and an hourly pass means a new
 * calendar day is picked up within the hour whatever timezone the server runs in — node-cron
 * here is pinned to UTC while term dates are local calendar days.
 */
export const renewalJob: JobDefinition = {
  name: 'membership.renewal',
  schedule: '20 * * * *',
  description:
    'Starts paid renewal terms, closes ended terms, expires members past grace, raises renewal invoices and sends reminders.',
  handler: async () => {
    const s = await runRenewalCycle();
    if (s.raised + s.expired + s.started + s.reminded > 0 || s.skipped.length > 0) {
      logger.info('membership.renewal', { ...s, skipped: s.skipped.length });
    }
    return s.closed + s.started + s.expired + s.raised + s.reminded;
  },
};
```
Add `renewalJob` to the `jobDefinitions` array.

- [ ] **Step 8: Verify** — `npm test && npm run typecheck && npm run lint`. Expected PASS.
- [ ] **Step 9: Checkpoint** — stop for the user; do not commit.

---

### Task 8: Admin API — buckets, list, run now

**Files:**
- Modify: `backend/src/modules/renewal/renewal.repository.ts` (add `bucketSummary`, `bucketRows`)
- Create: `backend/src/modules/renewal/renewal.types.ts`
- Create: `backend/src/modules/renewal/renewal.admin.service.ts`
- Create: `backend/src/modules/renewal/renewal.controller.ts`
- Create: `backend/src/modules/renewal/renewal.routes.ts`
- Modify: `backend/src/routes/index.ts`
- Test: `backend/src/modules/renewal/renewal.types.test.ts`

**Interfaces (frozen contract, consumed by Task 12):**
- `GET /api/v1/admin/renewals/summary` (`renewal.view`) → `{ due: number; grace: number; expired: number; notice_days: number; grace_days: number }`
- `GET /api/v1/admin/renewals?bucket=due|grace|expired&page=1&limit=20&search=` (`renewal.view`) → rows + pagination:
```ts
interface RenewalRow {
  member_id: string; member_code: string | null; company_name: string;
  plan_name: string | null; billing_cycle: string | null;
  valid_till: string;            // current term's last day, YYYY-MM-DD
  grace_ends_on: string;         // valid_till + grace_days
  renewal_term_id: string | null; renewal_status: string | null;
  invoice_id: string | null; invoice_number: string | null;
  invoice_total: string | null; invoice_status: string | null; claim_pending: boolean;
}
```
- `POST /api/v1/admin/renewals/run` (`renewal.manage`) → `CycleSummary` with `skipped` as strings; audit action `renewal.run`.

Bucket rules (one SQL, same CTE for summary and list — "every bucket count matches a single SQL query"):
- base: members (not deleted) joined to `current_term` with status `ACTIVE`/`EXPIRED`, **excluding** those with a `PAID_UPCOMING`/`ACTIVE` next term (`valid_from = valid_till + 1`).
- `due`: member `ACTIVE` and `today <= valid_till <= today + notice`.
- `grace`: member `ACTIVE` and `valid_till < today`.
- `expired`: member `EXPIRED`.

- [ ] **Step 1: Repository additions**

```ts
export type Bucket = 'due' | 'grace' | 'expired';

const bucketBase = () => Prisma.sql`
  WITH cur AS (
    SELECT m.id AS member_id, m.member_code, m.company_name, m.status AS member_status,
           t.valid_till, t.fee_plan_id
    FROM "Members" m
    JOIN "MembershipTerms" t ON t.id = m.current_term_id
    WHERE m."deletedAt" IS NULL
      AND t.status IN ('ACTIVE', 'EXPIRED')
      AND NOT EXISTS (
        SELECT 1 FROM "MembershipTerms" n
        WHERE n.member_id = m.id AND n.valid_from = t.valid_till + 1
          AND n.status IN ('PAID_UPCOMING', 'ACTIVE'))
  )`;

const bucketWhere = (bucket: Bucket, today: Date, horizon: Date) => {
  switch (bucket) {
    case 'due':
      return Prisma.sql`cur.member_status = 'ACTIVE' AND cur.valid_till BETWEEN ${isoDay(today)}::date AND ${isoDay(horizon)}::date`;
    case 'grace':
      return Prisma.sql`cur.member_status = 'ACTIVE' AND cur.valid_till < ${isoDay(today)}::date`;
    case 'expired':
      return Prisma.sql`cur.member_status = 'EXPIRED'`;
  }
};

export const bucketSummary = async (db: Db, today: Date, horizon: Date) => {
  const [row] = await db.$queryRaw<{ due: number; grace: number; expired: number }[]>(Prisma.sql`
    ${bucketBase()}
    SELECT
      COUNT(*) FILTER (WHERE ${bucketWhere('due', today, horizon)})::int     AS due,
      COUNT(*) FILTER (WHERE ${bucketWhere('grace', today, horizon)})::int   AS grace,
      COUNT(*) FILTER (WHERE ${bucketWhere('expired', today, horizon)})::int AS expired
    FROM cur
  `);
  return row ?? { due: 0, grace: 0, expired: 0 };
};

export interface BucketRow {
  member_id: bigint; member_code: string | null; company_name: string;
  plan_name: string | null; billing_cycle: string | null; valid_till: Date;
  renewal_term_id: bigint | null; renewal_status: string | null;
  invoice_id: bigint | null; invoice_number: string | null;
  invoice_total: Prisma.Decimal | null; invoice_status: string | null;
  claim_pending: boolean; total: number;
}

export const bucketRows = (
  db: Db,
  p: { bucket: Bucket; today: Date; horizon: Date; search: string | null; limit: number; offset: number },
) =>
  db.$queryRaw<BucketRow[]>(Prisma.sql`
    ${bucketBase()}
    SELECT cur.member_id, cur.member_code, cur.company_name,
           fp.name AS plan_name, fp.billing_cycle::text AS billing_cycle, cur.valid_till,
           n.id AS renewal_term_id, n.status::text AS renewal_status,
           i.id AS invoice_id, i.invoice_number, i.total_amount AS invoice_total,
           i.status::text AS invoice_status,
           EXISTS (SELECT 1 FROM "PaymentSubmissions" s
                   WHERE s.invoice_id = i.id AND s.status = ${SUBMISSION_STATUS.PENDING}) AS claim_pending,
           COUNT(*) OVER ()::int AS total
    FROM cur
    LEFT JOIN "FeePlans" fp ON fp.id = cur.fee_plan_id
    LEFT JOIN "MembershipTerms" n
      ON n.member_id = cur.member_id AND n.valid_from = cur.valid_till + 1 AND n.status <> 'CANCELLED'
    LEFT JOIN "Invoices" i ON i.id = n.invoice_id
    WHERE ${bucketWhere(p.bucket, p.today, p.horizon)}
      ${p.search ? Prisma.sql`AND (cur.company_name ILIKE ${`%${p.search}%`} OR cur.member_code ILIKE ${`%${p.search}%`})` : Prisma.empty}
    ORDER BY cur.valid_till ASC, cur.company_name ASC
    LIMIT ${p.limit} OFFSET ${p.offset}
  `);
```

- [ ] **Step 2: Types + failing test**

`renewal.types.ts`:
```ts
import { z } from 'zod';

export const bucketListSchema = z.object({
  bucket: z.enum(['due', 'grace', 'expired']).default('due'),
  page: z.coerce.number().int().min(1).default(1),
  // Clamped, never rejected — the list contract every admin list follows (testing-strategy §5).
  limit: z.coerce.number().int().min(1).default(20).transform((n) => Math.min(n, 100)),
  search: z.string().trim().max(100).optional(),
});
export type BucketListQuery = z.infer<typeof bucketListSchema>;

export const switchPlanSchema = z.object({
  fee_plan_id: z.string().regex(/^\d+$/, 'validation.invalidNumber'),
});
export type SwitchPlanBody = z.infer<typeof switchPlanSchema>;
```
`renewal.types.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { bucketListSchema, switchPlanSchema } from '@modules/renewal/renewal.types';

describe('renewal schemas', () => {
  it('defaults to the due bucket, page 1', () => {
    expect(bucketListSchema.parse({})).toMatchObject({ bucket: 'due', page: 1, limit: 20 });
  });
  it('clamps limit to 100', () => {
    expect(bucketListSchema.parse({ limit: '500' }).limit).toBe(100);
  });
  it('rejects an unknown bucket', () => {
    expect(() => bucketListSchema.parse({ bucket: 'overdue' })).toThrow();
  });
  it('requires a numeric plan id', () => {
    expect(() => switchPlanSchema.parse({ fee_plan_id: 'abc' })).toThrow();
  });
});
```
Run `npx vitest run src/modules/renewal/renewal.types.test.ts` → FAIL first, then PASS after creating the file.

- [ ] **Step 3: Admin service**

```ts
import { prisma } from '@db/prisma';
import { getNumericSetting, SETTING_KEYS } from '@helpers/settings';
import { addDays, dbToday, isoDay } from '@modules/renewal/renewal.dates';
import { runRenewalCycle } from '@modules/renewal/renewal.lifecycle';
import * as repo from '@modules/renewal/renewal.repository';
import type { BucketListQuery } from '@modules/renewal/renewal.types';

const windowNow = async () => {
  const today = dbToday();
  const noticeDays = await getNumericSetting(SETTING_KEYS.RENEWAL_NOTICE_DAYS, 15);
  const graceDays = await getNumericSetting(SETTING_KEYS.MEMBERSHIP_GRACE_DAYS, 30);
  return { today, noticeDays, graceDays, horizon: addDays(today, noticeDays) };
};

export const getSummary = async () => {
  const w = await windowNow();
  const counts = await repo.bucketSummary(prisma, w.today, w.horizon);
  return { ...counts, notice_days: w.noticeDays, grace_days: w.graceDays };
};

export const listBucket = async (q: BucketListQuery) => {
  const w = await windowNow();
  const rows = await repo.bucketRows(prisma, {
    bucket: q.bucket,
    today: w.today,
    horizon: w.horizon,
    search: q.search || null,
    limit: q.limit,
    offset: (q.page - 1) * q.limit,
  });
  const total = rows[0]?.total ?? 0;

  return {
    data: rows.map((r) => ({
      member_id: r.member_id.toString(),
      member_code: r.member_code,
      company_name: r.company_name,
      plan_name: r.plan_name,
      billing_cycle: r.billing_cycle,
      valid_till: isoDay(r.valid_till),
      grace_ends_on: isoDay(addDays(r.valid_till, w.graceDays)),
      renewal_term_id: r.renewal_term_id?.toString() ?? null,
      renewal_status: r.renewal_status,
      invoice_id: r.invoice_id?.toString() ?? null,
      invoice_number: r.invoice_number,
      invoice_total: r.invoice_total?.toFixed(2) ?? null,
      invoice_status: r.invoice_status,
      claim_pending: r.claim_pending,
    })),
    pagination: { page: q.page, limit: q.limit, total, totalPages: Math.ceil(total / q.limit) },
  };
};

/** "Generate Invoices": the same cycle the schedule runs — only members inside the window are billed. */
export const runNow = () => runRenewalCycle();
```
Check the pagination field names against what another admin list passes to `handleApiResponse` (e.g. `contact` admin list) and match them.

- [ ] **Step 4: Controller + routes**

`renewal.controller.ts` — follow `dashboard.controller.ts` (local `handler`, `handleApiResponse`). Admin handlers:
```ts
export const getAdminSummary = handler(async (_req, res) => {
  handleApiResponse(res, { responseType: RES_STATUS.GET, data: await admin.getSummary() });
});

export const listAdminBucket = handler(async (req, res) => {
  const { data, pagination } = await admin.listBucket(req.query as unknown as BucketListQuery);
  handleApiResponse(res, { responseType: RES_STATUS.GET, data, pagination });
});

export const runAdminCycle = handler(async (req, res) => {
  const summary = await admin.runNow();
  await writeAudit(prisma, {
    ...adminAuditFrom(req), // the same actor → audit fields member.controller builds for recordInvoicePayment
    action: 'renewal.run',
    entityName: 'MembershipTerms',
    entityId: null,
    before: null,
    after: { raised: summary.raised, skipped: summary.skipped.length, expired: summary.expired },
  });
  handleApiResponse(res, { responseType: RES_STATUS.ACTION, messageKey: 'renewal.runCompleted', data: summary });
});
```
Add `RENEWAL_RUN: 'renewal.run'` to `AUDIT_ACTIONS` in `src/constant/audit.constant.ts` and use the constant. For `adminAuditFrom(req)`, reuse whatever helper `member.controller.ts` uses to build the `Actor` it passes to `recordInvoicePayment` — do not write a second one.

`renewal.routes.ts`:
```ts
import { Router } from 'express';
import { authenticate, authenticateAdmin, authorize, validateRequest } from '@middleware';
import * as controller from '@modules/renewal/renewal.controller';
import { bucketListSchema, switchPlanSchema } from '@modules/renewal/renewal.types';

/** `/api/v1/admin/renewals` — A-20. Guards bound per path, like every router on the /admin mount. */
export const renewalAdminRouter = Router();
const RENEWALS = '/renewals';

renewalAdminRouter.get(`${RENEWALS}/summary`, authenticateAdmin, authorize('renewal.view'), controller.getAdminSummary);
renewalAdminRouter.get(RENEWALS, authenticateAdmin, authorize('renewal.view'), validateRequest({ query: bucketListSchema }), controller.listAdminBucket);
renewalAdminRouter.post(`${RENEWALS}/run`, authenticateAdmin, authorize('renewal.manage'), controller.runAdminCycle);

/** `/api/v1/membership/me/*` — the member's own term (C-18, C-23). */
export const renewalMemberRouter = Router();
renewalMemberRouter.use(authenticate);
renewalMemberRouter.get('/me/term', controller.getMyTerm);
renewalMemberRouter.get('/me/terms', controller.listMyTerms);
renewalMemberRouter.get('/me/renewal/plans', controller.listMyRenewalPlans);
renewalMemberRouter.post('/me/renewal/plan', validateRequest({ body: switchPlanSchema }), controller.switchMyRenewalPlan);
```
(The four member handlers are written in Task 11; until then export stubs that `throw new Error('not implemented')` so the router compiles — Task 11 replaces them.)

`src/routes/index.ts`:
```ts
import { renewalAdminRouter, renewalMemberRouter } from '@modules/renewal/renewal.routes';
// beside dashboardRouter:
router.use(`${END_POINTS.V1}${END_POINTS.ADMIN}`, renewalAdminRouter);
// beside the other member-facing mounts:
router.use(`${END_POINTS.V1}${END_POINTS.MEMBERSHIP}`, renewalMemberRouter);
```
Check first that nothing else is already mounted on `END_POINTS.MEMBERSHIP` with a router-wide guard that would shadow `/me/term`; if something is, mount the member router before it.

- [ ] **Step 5: Verify** — `npm test && npm run typecheck && npm run lint`. Then, with the backend dev server the user already has running (do not restart it), smoke:
```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" http://localhost:<port>/api/v1/admin/renewals/summary
```
Expected 200 (body encrypted per the envelope). If you cannot obtain a token, note it and leave the smoke to Task 15.
- [ ] **Step 6: Checkpoint** — stop for the user; do not commit.

---

### Task 9: Admin member detail reads the real current term

**Files:**
- Modify: `backend/src/modules/member/member.repository.ts` (:169–190)
- Modify: `admin/src/services/membersService.ts` (`MemberDetail`, ~:101–180)
- Modify: `admin/src/pages/members/ProfileTab.tsx` (:71, :421–456)

Why: `terms` is "newest `valid_till` first, take 1". Once a renewal exists that row is the **unpaid next** term, and the admin card would show next year's dates as current.

- [ ] **Step 1: Backend** — beside `terms`, add the member's actual current term (relation `current_term`, via `current_term_id`), with the same `select` block as `terms`:
```ts
      /* The term the member is covered by right now. `terms` (newest expiry) becomes the unpaid
         renewal as soon as one is raised, so "current" has to come from current_term_id. */
      current_term: {
        select: {
          id: true, term_type: true, valid_from: true, valid_till: true, status: true,
          fee_plan: { select: { id: true, name: true, billing_cycle: true, amount: true, renewal_amount: true, tax_rate: true, currency: true } },
        },
      },
```
Run `npm run typecheck && npm test` in `backend/`.

- [ ] **Step 2: Admin type** — in `MemberDetail` add `current_term?: MemberTerm | null;` where `MemberTerm` is the existing element type of `terms` (extract it to a named interface if it is inline).

- [ ] **Step 3: Admin card** — `ProfileTab.tsx:71`:
```ts
const currentTerm = member.current_term ?? member.terms?.[0] ?? null;
```
and in the "Membership plan" card, next to the Term dates line, render `<StatusChip domain="term" status={currentTerm.status} />`.

- [ ] **Step 4: Verify** — `cd admin && npm run typecheck && npm run lint`.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 10: Admin statuses, report filter, settings copy

**Files:**
- Modify: `admin/src/constant/status.ts` (:49–52)
- Modify: `admin/src/pages/reports/reportSpecs.ts` (`termStatus`, :138–143)
- Modify: `admin/src/pages/settings/SystemSettings.tsx` (`COPY` ~:269, `ROW_ORDER` ~:403)

- [ ] **Step 1: Status** — add after `'term.PENDING_PAYMENT'`:
```ts
  'term.PAID_UPCOMING': { variant: 'info', label: 'Paid, starts later' },
```
- [ ] **Step 2: Report filter** — add `{ value: 'PAID_UPCOMING', label: 'Paid, starts later' }` to `termStatus` in `reportSpecs.ts`, in the same position (after PENDING_PAYMENT), matching the existing entry shape.
- [ ] **Step 3: Settings copy** — first confirm whether the `'membership.grace_days'` COPY entry (:269) sits inside a `/* … */` block (the backend explorer flagged it). If it does, report it to the user and leave it. Then add, as a live entry next to it:
```ts
  'membership.renewal_notice_days': {
    label: 'Renewal notice days',
    help: 'How many days before a membership ends its renewal invoice is raised. Reminders follow at 7 and 3 days and on the last day.',
  },
```
and add `'membership.renewal_notice_days'` to `ROW_ORDER` directly after `'membership.grace_days'`.
- [ ] **Step 4: Verify** — `cd admin && npm run typecheck && npm run lint`. Open `http://localhost:3001/settings/system` in the running dev server: "Renewal notice days" shows 15 beside "Membership grace days" and saves.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 11: Member API — term view, history, plans, plan switch

**Files:**
- Create: `backend/src/modules/renewal/renewal.member.service.ts`
- Modify: `backend/src/modules/renewal/renewal.controller.ts` (replace the Task 8 stubs)
- Test: `backend/src/modules/renewal/renewal.member.service.test.ts`

**Interfaces (frozen contract, consumed by Tasks 13–14):**
```ts
// GET /api/v1/membership/me/term
interface TermView {
  state: TermState;                    // Task 4
  member_status: string;
  today: string;
  days_left: number | null;            // to current.valid_till
  grace_ends_on: string | null;        // current.valid_till + grace_days
  notice_days: number;
  current_term: null | {
    id: string; term_type: 'NEW' | 'RENEWAL'; status: string; valid_from: string; valid_till: string;
    plan: null | { id: string; name: string; billing_cycle: string; renewal_amount: string; tax_rate: string; currency: string };
  };
  renewal: null | {
    term_id: string; status: 'PENDING_PAYMENT' | 'PAID_UPCOMING'; valid_from: string; valid_till: string;
    plan_name: string | null;
    invoice: null | { id: string; invoice_number: string; total_amount: string; currency: string; due_date: string; status: string; pending_claim: boolean };
  };
  can_change_plan: boolean;            // renewal PENDING_PAYMENT, invoice ISSUED/OVERDUE, no pending claim
}
// GET /api/v1/membership/me/terms → TermHistoryRow[] (newest first, max 50, CANCELLED excluded)
interface TermHistoryRow { id: string; term_type: string; status: string; valid_from: string; valid_till: string; plan_name: string | null; invoice_number: string | null; total_amount: string | null }
// GET /api/v1/membership/me/renewal/plans → RenewalPlanOption[] (plans live today)
interface RenewalPlanOption { id: string; name: string; billing_cycle: string; duration_months: number; renewal_amount: string; tax_rate: string; renewal_total: string; currency: string; is_current: boolean }
// POST /api/v1/membership/me/renewal/plan { fee_plan_id } → TermView
//   404 renewal.noPendingRenewal · 409 renewal.claimPending · 409 renewal.planNotAvailable · 409 renewal.samePlan
```

`switchRenewalPlan(memberId, feePlanId)`, one transaction:
1. Advisory lock (same key as Task 5).
2. Find the member's `RENEWAL` term with status `PENDING_PAYMENT` and its invoice; none → 404 `renewal.noPendingRenewal`.
3. Invoice not `ISSUED`/`OVERDUE` (e.g. partly paid) or a `PENDING` payment submission exists → 409 `renewal.claimPending`.
4. `loadLivePlan(tx, feePlanId, today)`; null → 409 `renewal.planNotAvailable`; same id as the term's `fee_plan_id` → 409 `renewal.samePlan`.
5. Invoice → `CANCELLED` and term → `CANCELLED` (audit `INVOICE_CANCELLED`, member actor). Look for an existing invoice-cancel path (`grep -rn INVOICE_CANCELLED backend/src`) and set the same fields it sets.
6. Find the member's current term (`current_term_id`) for `categoryId`/`tierId`, then `raiseRenewal(tx, { memberId, categoryId, tierId, feePlanId: null, previousValidTill: addDays(cancelledTerm.valid_from, -1) }, { today, basis, dueDays, planOverride: plan })` → must return `RAISED` (anything else → throw conflict `renewal.planNotAvailable`).
7. Return `getMyTermView(memberId)`.

Reminder rows belong to the cancelled term, so the new term gets today's stage message with the new amount on the next job pass — intended.

- [ ] **Step 1: Write the failing tests** — mock `@db/prisma` (`$transaction: (fn) => fn(tx)`), `@modules/renewal/renewal.pricing` (`loadLivePlan`), `@modules/renewal/renewal.raise` (`raiseRenewal`):
```ts
describe('switchRenewalPlan', () => {
  it('404s when no renewal is waiting', …expect code NOT_FOUND / messageKey renewal.noPendingRenewal);
  it('refuses while a payment claim is being checked', …renewal.claimPending);
  it('refuses a plan that is not on sale', …loadLivePlan → null → renewal.planNotAvailable);
  it('refuses the same plan', …renewal.samePlan);
  it('cancels the old invoice and term, then raises on the chosen plan from the same start date', async () => {
    // arrange: pending term { id: 20n, valid_from: 2027-04-01, fee_plan_id: 7n, invoice: { id: 30n, status: 'ISSUED' } }
    // act: switchRenewalPlan(5n, 8n)
    // assert: invoice 30n → CANCELLED, term 20n → CANCELLED,
    //   raiseRenewal called with previousValidTill 2027-03-31 and planOverride.id 8n
  });
});
```
The outline above is the case list; the full file is:

```ts
import { Prisma } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);

const memberFindFirst = vi.fn();
const termFindFirst = vi.fn();
const termUpdate = vi.fn();
const invoiceUpdate = vi.fn();
const executeRaw = vi.fn();
const loadLivePlan = vi.fn();
const raiseRenewal = vi.fn();

const tx = {
  $executeRaw: executeRaw,
  member: { findFirst: memberFindFirst },
  membershipTerm: { findFirst: termFindFirst, update: termUpdate },
  invoice: { update: invoiceUpdate },
};

vi.mock('@db/prisma', () => ({
  prisma: { ...tx, $transaction: (fn: (t: unknown) => unknown) => fn(tx) },
}));
vi.mock('@helpers/settings', async (orig) => ({
  ...(await orig<typeof import('@helpers/settings')>()),
  getSetting: vi.fn(async () => 'term'),
  getNumericSetting: vi.fn(async (_k: string, fallback: number) => fallback),
}));
vi.mock('@helpers/audit', () => ({ writeAudit: vi.fn(async () => undefined) }));
vi.mock('@modules/renewal/renewal.pricing', async (orig) => ({
  ...(await orig<typeof import('@modules/renewal/renewal.pricing')>()),
  loadLivePlan: (...a: unknown[]) => loadLivePlan(...a),
}));
vi.mock('@modules/renewal/renewal.raise', () => ({ raiseRenewal: (...a: unknown[]) => raiseRenewal(...a) }));

const service = await import('@modules/renewal/renewal.member.service');
// getMyTermView is called at the end of a successful switch; its own behaviour is covered
// by termState (Task 4) and the Sentinel suite, so it is stubbed here.
vi.spyOn(service, 'getMyTermView').mockResolvedValue({ state: 'EXPIRING_SOON' } as never);

const AUDIT = { actorId: 3n, ip: null, userAgent: null, requestId: null };
const CURRENT = { valid_till: day('2027-03-31'), category_id: 2n, tier_id: null };
const pending = (over: Record<string, unknown> = {}) => ({
  id: 20n, status: 'PENDING_PAYMENT', valid_from: day('2027-04-01'), fee_plan_id: 7n,
  invoice: { id: 30n, status: 'ISSUED', paymentSubmissions: [] }, ...over,
});
const PLAN_8 = { id: 8n, billing_cycle: 'MONTHLY', name: 'Starter', renewal_amount: new Prisma.Decimal('2500'),
  tax_rate: new Prisma.Decimal('18'), currency: 'INR', effective_from: day('2026-04-01'), effective_to: null,
  is_active: true, price_scope: 'ALL_MEMBERS' };

const run = () => service.switchRenewalPlan(5n, 8n, AUDIT);

describe('switchRenewalPlan', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    memberFindFirst.mockResolvedValue({ current_term: CURRENT });
    termFindFirst.mockResolvedValue(pending());
    loadLivePlan.mockResolvedValue(PLAN_8);
    raiseRenewal.mockResolvedValue({ outcome: 'RAISED', termId: 21n, invoiceId: 31n, invoiceNumber: 'IN2', total: '2950.00' });
  });

  it('404s when no renewal is waiting', async () => {
    termFindFirst.mockResolvedValue(null);
    await expect(run()).rejects.toMatchObject({ messageKey: 'renewal.noPendingRenewal' });
  });

  it('refuses while a payment claim is being checked', async () => {
    termFindFirst.mockResolvedValue(pending({ invoice: { id: 30n, status: 'ISSUED', paymentSubmissions: [{ id: 1n }] } }));
    await expect(run()).rejects.toMatchObject({ messageKey: 'renewal.claimPending' });
    expect(invoiceUpdate).not.toHaveBeenCalled();
  });

  it('refuses a plan that is not on sale', async () => {
    loadLivePlan.mockResolvedValue(null);
    await expect(run()).rejects.toMatchObject({ messageKey: 'renewal.planNotAvailable' });
  });

  it('refuses the same plan', async () => {
    termFindFirst.mockResolvedValue(pending({ fee_plan_id: 8n }));
    await expect(run()).rejects.toMatchObject({ messageKey: 'renewal.samePlan' });
  });

  it('cancels the old invoice and term, then raises on the chosen plan from the same start date', async () => {
    await run();
    expect(invoiceUpdate).toHaveBeenCalledWith({ where: { id: 30n }, data: { status: 'CANCELLED' } });
    expect(termUpdate).toHaveBeenCalledWith({ where: { id: 20n }, data: { status: 'CANCELLED' } });
    const [, src, opts] = raiseRenewal.mock.calls[0];
    expect(src).toMatchObject({ memberId: 5n, categoryId: 2n, feePlanId: null });
    expect(src.previousValidTill.toISOString().slice(0, 10)).toBe('2027-03-31');
    expect(opts.planOverride.id).toBe(8n);
  });
});
```
If `vi.spyOn` on the ESM namespace is rejected by the Vitest config, call `getMyTermView` through an internal `deps` object or drop that spy and mock `tx.member.findFirst` for the final read as well — do not weaken the four assertions above.

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/modules/renewal/renewal.member.service.test.ts` → FAIL (module missing).
- [ ] **Step 3: Implement** `renewal.member.service.ts`. Import `AppError` and `ERROR_TYPES` from the same paths `activation.service.ts` imports them; the pending claim status is the smallint `SUBMISSION_STATUS.PENDING` from `src/modules/event/registration.constants.ts` — never the string `'PENDING'` (which matches nothing).

```ts
import { InvoiceStatus, TermStatus, TermType } from '@prisma/client';
import { prisma, type Db } from '@db/prisma';
import { ACTOR_TYPES, AUDIT_ACTIONS } from '@constant/audit.constant';
import { writeAudit } from '@helpers/audit';
import { getNumericSetting, getSetting, SETTING_KEYS, type RenewalBasis } from '@helpers/settings';
import { CYCLE_MONTHS, listPublicPlans } from '@modules/masters/masters.feePlans.service';
import { addDays, daysBetween, dbToday, isoDay } from '@modules/renewal/renewal.dates';
import { loadLivePlan } from '@modules/renewal/renewal.pricing';
import { raiseRenewal } from '@modules/renewal/renewal.raise';
import { termState } from '@modules/renewal/renewal.state';
import { SUBMISSION_STATUS } from '@modules/event/registration.constants';
// import { AppError, ERROR_TYPES } from '<same as activation.service.ts>';

const WAITING = [TermStatus.PENDING_PAYMENT, TermStatus.PAID_UPCOMING];
const SWITCHABLE_INVOICE: InvoiceStatus[] = [InvoiceStatus.ISSUED, InvoiceStatus.OVERDUE];

const notFound = (messageKey: string) => new AppError({ errorType: ERROR_TYPES.NOT_FOUND, messageKey });
const conflict = (messageKey: string) => new AppError({ errorType: ERROR_TYPES.CONFLICT, messageKey });

/** The renewal waiting behind the current term, with its invoice and any claim being checked. */
const nextTerm = (db: Db, memberId: bigint, after: Date) =>
  db.membershipTerm.findFirst({
    where: { member_id: memberId, term_type: TermType.RENEWAL, status: { in: WAITING }, valid_from: { gt: after } },
    orderBy: { valid_from: 'asc' },
    include: {
      fee_plan: { select: { name: true } },
      invoice: { include: { paymentSubmissions: { where: { status: SUBMISSION_STATUS.PENDING }, select: { id: true } } } },
    },
  });

export const getMyTermView = async (memberId: bigint, now: Date = new Date()) => {
  const today = dbToday(now);
  const noticeDays = await getNumericSetting(SETTING_KEYS.RENEWAL_NOTICE_DAYS, 15);
  const graceDays = await getNumericSetting(SETTING_KEYS.MEMBERSHIP_GRACE_DAYS, 30);

  const member = await prisma.member.findFirst({
    where: { id: memberId, deletedAt: null },
    select: {
      status: true,
      current_term: {
        select: {
          id: true, term_type: true, status: true, valid_from: true, valid_till: true,
          fee_plan: { select: { id: true, name: true, billing_cycle: true, renewal_amount: true, tax_rate: true, currency: true } },
        },
      },
    },
  });
  if (!member) throw notFound('member.notFound');

  const current = member.current_term;
  const next = current ? await nextTerm(prisma, memberId, current.valid_till) : null;
  const invoice = next?.invoice ?? null;
  const pendingClaim = Boolean(invoice && invoice.paymentSubmissions.length > 0);

  return {
    state: termState({
      memberStatus: member.status,
      current: current ? { status: current.status, valid_till: current.valid_till } : null,
      renewalStatus: next?.status ?? null,
      today,
      noticeDays,
    }),
    member_status: member.status,
    today: isoDay(today),
    days_left: current ? daysBetween(today, current.valid_till) : null,
    grace_ends_on: current ? isoDay(addDays(current.valid_till, graceDays)) : null,
    notice_days: noticeDays,
    current_term: current && {
      id: current.id.toString(),
      term_type: current.term_type,
      status: current.status,
      valid_from: isoDay(current.valid_from),
      valid_till: isoDay(current.valid_till),
      plan: current.fee_plan && {
        id: current.fee_plan.id.toString(),
        name: current.fee_plan.name,
        billing_cycle: current.fee_plan.billing_cycle,
        renewal_amount: current.fee_plan.renewal_amount.toFixed(2),
        tax_rate: current.fee_plan.tax_rate.toFixed(2),
        currency: current.fee_plan.currency,
      },
    },
    renewal: next && {
      term_id: next.id.toString(),
      status: next.status,
      valid_from: isoDay(next.valid_from),
      valid_till: isoDay(next.valid_till),
      plan_name: next.fee_plan?.name ?? null,
      invoice: invoice && {
        id: invoice.id.toString(),
        invoice_number: invoice.invoice_number,
        total_amount: invoice.total_amount.toFixed(2),
        currency: invoice.currency,
        due_date: isoDay(invoice.due_date),
        status: invoice.status,
        pending_claim: pendingClaim,
      },
    },
    can_change_plan:
      next?.status === TermStatus.PENDING_PAYMENT &&
      invoice !== null &&
      SWITCHABLE_INVOICE.includes(invoice.status) &&
      !pendingClaim,
  };
};

export const listMyTerms = async (memberId: bigint) => {
  const rows = await prisma.membershipTerm.findMany({
    where: { member_id: memberId, status: { not: TermStatus.CANCELLED } },
    orderBy: { valid_from: 'desc' },
    take: 50,
    include: { fee_plan: { select: { name: true } }, invoice: { select: { invoice_number: true, total_amount: true } } },
  });
  return rows.map((t) => ({
    id: t.id.toString(),
    term_type: t.term_type,
    status: t.status,
    valid_from: isoDay(t.valid_from),
    valid_till: isoDay(t.valid_till),
    plan_name: t.fee_plan?.name ?? null,
    invoice_number: t.invoice?.invoice_number ?? null,
    total_amount: t.invoice?.total_amount.toFixed(2) ?? null,
  }));
};

export const listMyRenewalPlans = async (memberId: bigint) => {
  const member = await prisma.member.findFirst({
    where: { id: memberId },
    select: { current_term: { select: { valid_till: true, fee_plan_id: true } } },
  });
  const next = member?.current_term ? await nextTerm(prisma, memberId, member.current_term.valid_till) : null;
  const currentPlanId = next?.fee_plan_id ?? member?.current_term?.fee_plan_id ?? null;

  const plans = await listPublicPlans();
  return plans.map((p) => {
    const tax = p.renewal_amount.mul(p.tax_rate).div(100).toDecimalPlaces(2);
    return {
      id: p.id.toString(),
      name: p.name,
      billing_cycle: p.billing_cycle,
      duration_months: CYCLE_MONTHS[p.billing_cycle],
      renewal_amount: p.renewal_amount.toFixed(2),
      tax_rate: p.tax_rate.toFixed(2),
      renewal_total: p.renewal_amount.add(tax).toFixed(2),
      currency: p.currency,
      is_current: currentPlanId !== null && p.id === currentPlanId,
    };
  });
};

/** C-23: switch plan while the renewal invoice is unpaid (decided 2026-09-10). */
export const switchRenewalPlan = async (
  memberId: bigint,
  feePlanId: bigint,
  audit: { actorId: bigint; ip: string | null; userAgent: string | null; requestId: string | null },
) => {
  const today = dbToday();
  const basis = ((await getSetting(SETTING_KEYS.RENEWAL_BASIS)) ?? 'term') as RenewalBasis;
  const dueDays = await getNumericSetting(SETTING_KEYS.INVOICE_DUE_DAYS, 15);

  await prisma.$transaction(async (tx) => {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext('membership.renewal'), (${memberId} % 2147483647)::int)`;

    const member = await tx.member.findFirst({
      where: { id: memberId },
      select: { current_term: { select: { valid_till: true, category_id: true, tier_id: true } } },
    });
    const current = member?.current_term;
    if (!current) throw notFound('renewal.noPendingRenewal');

    const next = await nextTerm(tx, memberId, current.valid_till);
    if (!next || next.status !== TermStatus.PENDING_PAYMENT || !next.invoice) {
      throw notFound('renewal.noPendingRenewal');
    }
    if (!SWITCHABLE_INVOICE.includes(next.invoice.status) || next.invoice.paymentSubmissions.length > 0) {
      throw conflict('renewal.claimPending');
    }

    const plan = await loadLivePlan(tx, feePlanId, today);
    if (!plan) throw conflict('renewal.planNotAvailable');
    if (plan.id === next.fee_plan_id) throw conflict('renewal.samePlan');

    // Cancel first: the partial unique index ignores CANCELLED, so the new term can take the
    // same start date in the same transaction.
    await tx.invoice.update({ where: { id: next.invoice.id }, data: { status: InvoiceStatus.CANCELLED } });
    await tx.membershipTerm.update({ where: { id: next.id }, data: { status: TermStatus.CANCELLED } });
    await writeAudit(tx, {
      actorType: ACTOR_TYPES.MEMBER,
      ...audit,
      action: AUDIT_ACTIONS.INVOICE_CANCELLED,
      entityName: 'Invoices',
      entityId: next.invoice.id,
      before: { status: next.invoice.status },
      after: { status: InvoiceStatus.CANCELLED, reason: 'Plan switched at renewal' },
    });

    const result = await raiseRenewal(
      tx,
      {
        memberId,
        categoryId: current.category_id,
        tierId: current.tier_id,
        feePlanId: null,
        previousValidTill: addDays(next.valid_from, -1),
      },
      { today, basis, dueDays, planOverride: plan },
    );
    if (result.outcome !== 'RAISED') throw conflict('renewal.planNotAvailable');
  });

  return getMyTermView(memberId);
};
```
If an invoice-cancel path already exists (`grep -rn INVOICE_CANCELLED backend/src`), set the same extra fields it sets (e.g. `balance_due`). If `ACTOR_TYPES` has no `MEMBER` key, use the value the member-side audit rows already use.

Details the controller needs:
  - `switchMyRenewalPlan` passes `{ actorId, ip, userAgent, requestId }` as `audit` — build it the same way the member-side claim route builds its actor for `submitInvoiceClaim` (`member.controller.ts`), so member audit rows look alike.
  - All four handlers return the service result as `data` (ids are already strings, dates `YYYY-MM-DD`).
- [ ] **Step 4: Controller handlers** — resolve the member exactly as `member.controller.ts` `ownMember(req)` does (`service.getOrCreateOwnMember(current.id, current)`), then call the service; `switchMyRenewalPlan` responds with `RES_STATUS.ACTION`, `messageKey: 'renewal.planChanged'`.
- [ ] **Step 5: Verify** — `npm test && npm run typecheck && npm run lint`.
- [ ] **Step 6: Checkpoint** — stop for the user; do not commit.

---

### Task 12: Admin Renewals screen (A-20)

**Before starting:** invoke the `association-admin-ui` skill.

**Files:**
- Create: `admin/src/services/renewalsService.ts`
- Create: `admin/src/pages/renewals/Renewals.tsx`
- Modify: `admin/src/constant/endpoints.ts`, `admin/src/constant/navigation.tsx` (Work group, after `change-requests` :132), `admin/src/routes/AppRoutes.tsx` (explicit route + exclusion list :448–467)

**Interfaces:** consumes the Task 8 contract.

- [ ] **Step 1: Endpoints + service**

`endpoints.ts`:
```ts
  RENEWALS: {
    SUMMARY: '/admin/renewals/summary',
    LIST: '/admin/renewals',
    RUN: '/admin/renewals/run',
  },
```
`renewalsService.ts` (same shape as `enquiriesService.ts`):
```ts
import { ENDPOINTS } from '@/constant/endpoints';
import BaseService, { type ApiResult } from '@/services/BaseService';

export type RenewalBucket = 'due' | 'grace' | 'expired';

export interface RenewalSummary { due: number; grace: number; expired: number; notice_days: number; grace_days: number }

export interface RenewalRow {
  member_id: string; member_code: string | null; company_name: string;
  plan_name: string | null; billing_cycle: string | null;
  valid_till: string; grace_ends_on: string;
  renewal_term_id: string | null; renewal_status: string | null;
  invoice_id: string | null; invoice_number: string | null;
  invoice_total: string | null; invoice_status: string | null; claim_pending: boolean;
}

export interface RenewalRunResult {
  closed: number; started: number; expired: number; raised: number; reminded: number;
  skipped: { member_code: string | null; company_name: string; reason: string }[];
}

const query = (params: Record<string, string | number | undefined>) => {
  const qs = new URLSearchParams();
  Object.entries(params).forEach(([k, v]) => { if (v !== undefined && v !== '') qs.set(k, String(v)); });
  const s = qs.toString();
  return s ? `?${s}` : '';
};

const RenewalsService = {
  summary: (): Promise<ApiResult<RenewalSummary>> => BaseService.get(ENDPOINTS.RENEWALS.SUMMARY),
  list: (params: { bucket: RenewalBucket; page: number; limit: number; search?: string }): Promise<ApiResult<RenewalRow[]>> =>
    BaseService.get(`${ENDPOINTS.RENEWALS.LIST}${query(params)}`),
  run: (): Promise<ApiResult<RenewalRunResult>> => BaseService.post(ENDPOINTS.RENEWALS.RUN, {}),
};

export default RenewalsService;
```
Match `ApiResult`'s import path to how `enquiriesService.ts` imports it.

- [ ] **Step 2: Nav + route**

`navigation.tsx` (import `RefreshCw` from `lucide-react`), after the `change-requests` item:
```ts
      { key: 'renewals', label: 'Renewals', path: '/renewals', icon: RefreshCw, anyOf: ['renewal.view'], module: 'M6' },
```
`AppRoutes.tsx`: add `'/renewals'` to the exclusion list and an explicit route beside the other billing routes:
```tsx
<Route path="/renewals" element={<RequirePermission anyOf={['renewal.view']}><Renewals /></RequirePermission>} />
```

- [ ] **Step 3: Page** — `pages/renewals/Renewals.tsx`:

```tsx
import { Eye } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import {
  Badge, Button, Card, ConfirmDialog, DataTable, DateCell, Highlight, MoneyText, NotAvailable,
  PageHeader, PermissionGate, RowActions, SearchInput, StatusChip, Tabs, TextCell, toast,
} from '@/components/ui';
import { useConfirm } from '@/hooks/useConfirm';
import type { PaginationMeta } from '@/services/BaseService';
import RenewalsService, { type RenewalBucket, type RenewalRow, type RenewalSummary } from '@/services/renewalsService';

/**
 * A-20 — renewals by bucket.
 *
 * Current state: three buckets, each counted by the same SQL that lists it.
 * Required action: chase the grace bucket; "Generate Invoices" re-runs the renewal job now.
 * Next step / expected result: the member pays their renewal invoice and leaves the list.
 */

interface ApiError { message: string; requestId?: string }
const asError = (err: unknown): ApiError =>
  typeof err === 'object' && err !== null && 'message' in err ? (err as ApiError) : { message: 'Something went wrong' };

const REASON: Record<string, string> = {
  NO_PLAN: 'no plan on record',
  NO_PRICE: 'plan has no renewal price',
  ALREADY_RAISED: 'already raised',
  FAILED: 'failed — see logs',
};

const BucketTable = ({ bucket, search, refreshKey }: { bucket: RenewalBucket; search: string; refreshKey: number }) => {
  const navigate = useNavigate();
  const [rows, setRows] = useState<RenewalRow[]>([]);
  const [pagination, setPagination] = useState<PaginationMeta | undefined>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<ApiError | null>(null);
  const [page, setPage] = useState(1);

  useEffect(() => setPage(1), [search, bucket]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await RenewalsService.list({ bucket, page, limit: 20, ...(search ? { search } : {}) });
      setRows(res.data);
      setPagination(res.pagination);
    } catch (err) {
      setError(asError(err));
    } finally {
      setLoading(false);
    }
  }, [bucket, page, search]);

  useEffect(() => { void load(); }, [load, refreshKey]);

  return (
    <Card flush className="min-h-0 flex-1">
      <DataTable<RenewalRow>
        unit="members"
        serial
        rowKey="member_id"
        loading={loading}
        error={error}
        onRetry={() => void load()}
        pagination={pagination}
        onPageChange={setPage}
        dataSource={rows}
        filtered={Boolean(search)}
        emptyTitle={bucket === 'due' ? 'Nobody is due' : bucket === 'grace' ? 'Nobody is in grace' : 'No expired members'}
        emptyDescription={
          bucket === 'due'
            ? 'Members whose membership ends within the notice window appear here once their renewal invoice is raised.'
            : bucket === 'grace'
              ? 'Members whose membership has ended but who are still inside the grace period appear here.'
              : 'Members who did not renew before grace ended appear here. They can still sign in and pay.'
        }
        columns={[
          { title: 'Member', dataIndex: 'company_name', width: 240, render: (v: string) => <Highlight text={v} query={search} /> },
          { title: 'Member No.', dataIndex: 'member_code', width: 160, render: (v: string | null) => (v ? <Highlight text={v} query={search} /> : <NotAvailable />) },
          { title: 'Plan', dataIndex: 'plan_name', width: 160, render: (v: string | null) => (v ? <TextCell value={v} /> : <NotAvailable />) },
          { title: 'Ends On', dataIndex: 'valid_till', width: 130, render: (v: string) => <DateCell value={v} /> },
          ...(bucket === 'grace'
            ? [{ title: 'Grace Ends', dataIndex: 'grace_ends_on', width: 130, render: (v: string) => <DateCell value={v} /> }]
            : []),
          { title: 'Renewal Invoice', dataIndex: 'invoice_number', width: 160, render: (v: string | null) => (v ? <TextCell value={v} /> : <NotAvailable label="Not raised" />) },
          { title: 'Amount', dataIndex: 'invoice_total', width: 130, render: (v: string | null) => (v ? <MoneyText amount={v} /> : <NotAvailable />) },
          {
            title: 'Status',
            dataIndex: 'invoice_status',
            render: (_: unknown, row: RenewalRow) =>
              row.claim_pending ? <StatusChip domain="payment" status="PENDING" />
              : row.invoice_status ? <StatusChip domain="invoice" status={row.invoice_status} />
              : <NotAvailable />,
          },
          {
            title: 'Actions', width: 80, fixed: 'right' as const,
            render: (_: unknown, row: RenewalRow) => (
              <RowActions actions={[{ key: 'view', icon: <Eye size={16} />, label: 'Open member', onClick: () => navigate(`/members/${row.member_id}`) }]} />
            ),
          },
        ]}
      />
    </Card>
  );
};

export const Renewals = () => {
  const [summary, setSummary] = useState<RenewalSummary | null>(null);
  const [search, setSearch] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);
  const run = useConfirm<true>();

  const loadSummary = useCallback(async () => {
    try {
      setSummary((await RenewalsService.summary()).data);
    } catch (err) {
      toast.error(asError(err).message);
    }
  }, []);

  useEffect(() => { void loadSummary(); }, [loadSummary, refreshKey]);

  const count = (n: number | undefined) => <Badge>{n === undefined ? '…' : String(n)}</Badge>;

  const toolbar = (
    <>
      <SearchInput value={search} onChange={setSearch} placeholder="Company or member no." />
      <PermissionGate permission="renewal.manage">
        <Button variant="primary" onClick={() => run.ask(true)}>Generate Invoices</Button>
      </PermissionGate>
    </>
  );

  return (
    <div className="flex h-full min-h-0 flex-col">
      <PageHeader title="Renewals" />
      <Tabs
        variant="pill"
        queryParam="bucket"
        defaultTab="due"
        actions={toolbar}
        items={[
          { key: 'due', label: <span className="flex items-center gap-2">Due Soon {count(summary?.due)}</span>, children: <BucketTable bucket="due" search={search} refreshKey={refreshKey} /> },
          { key: 'grace', label: <span className="flex items-center gap-2">In Grace {count(summary?.grace)}</span>, children: <BucketTable bucket="grace" search={search} refreshKey={refreshKey} /> },
          { key: 'expired', label: <span className="flex items-center gap-2">Expired {count(summary?.expired)}</span>, children: <BucketTable bucket="expired" search={search} refreshKey={refreshKey} /> },
        ]}
      />

      <ConfirmDialog
        open={run.target !== null}
        danger={false}
        title="Generate renewal invoices now?"
        description={`Raises renewal invoices for members whose membership ends within the next ${summary?.notice_days ?? 15} days and who do not have one yet, and sends today's reminders. Nobody else is billed early. Safe to run more than once.`}
        confirmLabel="Generate Invoices"
        loading={run.busy}
        onCancel={run.cancel}
        onConfirm={() =>
          run.confirm(async () => {
            const { data } = await RenewalsService.run();
            const blocked = data.skipped.filter((s) => s.reason !== 'ALREADY_RAISED');
            toast.success(`${data.raised} renewal invoice${data.raised === 1 ? '' : 's'} raised.`, {
              description: blocked.length
                ? `Not raised: ${blocked.map((s) => `${s.company_name} (${REASON[s.reason] ?? s.reason})`).join(', ')}.`
                : undefined,
            });
            setRefreshKey((k) => k + 1);
          })
        }
      />
    </div>
  );
};

export default Renewals;
```
If `Tabs` `label` only accepts a string, use `` `Due Soon (${summary?.due ?? '…'})` `` instead and keep everything else. If `useConfirm().confirm` does not swallow errors, wrap the body in try/catch with `toast.error(asError(err).message)` as `Registrations.tsx` does.

- [ ] **Step 4: Verify** — `cd admin && npm run typecheck && npm run lint`. In the running admin dev server open `/renewals`: nav item visible for Super Admin, three tabs with counts, empty states read correctly, Generate Invoices shows the confirm and a result toast.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 13: Customer — types, service, banner copy, banner

**Files:**
- Create: `customer/src/types/renewal.ts`, `customer/src/services/RenewalService.ts`, `customer/src/components/renewal/renewalCopy.ts`, `customer/src/components/renewal/MembershipBanner.tsx`, `customer/scripts/verify-renewal.ts`
- Modify: `customer/src/constants/endpoints.ts`, `customer/src/components/layout/MemberShell.tsx` (inside `<main>`, above `{children}`), `customer/src/components/ui/statusMap.ts`, `customer/package.json`

**Interfaces:** consumes the Task 11 contract.

- [ ] **Step 1: Types** — `src/types/renewal.ts`: copy `TermView`, `TermHistoryRow`, `RenewalPlanOption` from Task 11 verbatim as exported interfaces; `export type TermState = 'NONE' | 'INACTIVE' | 'AWAITING_FIRST_PAYMENT' | 'ACTIVE' | 'EXPIRING_SOON' | 'RENEWED' | 'IN_GRACE' | 'EXPIRED';` plus
```ts
export function normaliseTermView(raw: unknown): TermView {
  const v = (raw ?? {}) as Partial<TermView>;
  return {
    state: v.state ?? 'NONE',
    member_status: v.member_status ?? 'DRAFT',
    today: v.today ?? '',
    days_left: v.days_left ?? null,
    grace_ends_on: v.grace_ends_on ?? null,
    notice_days: v.notice_days ?? 15,
    current_term: v.current_term ?? null,
    renewal: v.renewal ?? null,
    can_change_plan: Boolean(v.can_change_plan),
  };
}
```
- [ ] **Step 2: Endpoints + service**
```ts
// endpoints.ts
  membershipTerm: '/membership/me/term',
  membershipTerms: '/membership/me/terms',
  renewalPlans: '/membership/me/renewal/plans',
  renewalPlan: '/membership/me/renewal/plan',
```
```ts
'use client';
import { ENDPOINTS } from '@/constants/endpoints';
import { normaliseTermView, type RenewalPlanOption, type TermHistoryRow, type TermView } from '@/types/renewal';
import ApiService from './ApiService';

const RenewalService = {
  async getTerm(): Promise<TermView> {
    return normaliseTermView((await ApiService.get<unknown>(ENDPOINTS.membershipTerm)).data);
  },
  async listTerms(): Promise<TermHistoryRow[]> {
    return ((await ApiService.get<TermHistoryRow[]>(ENDPOINTS.membershipTerms)).data ?? []) as TermHistoryRow[];
  },
  async listPlans(): Promise<RenewalPlanOption[]> {
    return ((await ApiService.get<RenewalPlanOption[]>(ENDPOINTS.renewalPlans)).data ?? []) as RenewalPlanOption[];
  },
  async changePlan(feePlanId: string): Promise<TermView> {
    return normaliseTermView((await ApiService.post<unknown>(ENDPOINTS.renewalPlan, { fee_plan_id: feePlanId })).data);
  },
};
export default RenewalService;
```
- [ ] **Step 3: Status map** — add a `term` domain (`StatusDomain` union + `STATUS_MAP`):
```ts
const TERM: Record<string, StatusDescriptor> = {
  PENDING_PAYMENT: { variant: 'warning', label: 'Awaiting payment', icon: 'clock' },
  PAID_UPCOMING: { variant: 'info', label: 'Paid, starts later', icon: 'check' },
  ACTIVE: { variant: 'success', label: 'Active', icon: 'check' },
  EXPIRED: { variant: 'neutral', label: 'Ended', icon: 'expired' },
  CANCELLED: { variant: 'neutral', label: 'Cancelled', icon: 'cross' },
};
```
- [ ] **Step 4: Banner copy (pure) + failing verify script**

`src/components/renewal/renewalCopy.ts`:
```ts
import type { TermView } from '@/types/renewal';

export interface BannerCopy {
  variant: 'info' | 'warning' | 'danger';
  title: string;
  body: string;
  action: { label: string; href: string } | null;
}

export const MEMBERSHIP_PAGE = '/application/membership';

/**
 * The one sentence a member sees on every screen while their renewal needs them.
 * Current state → required action → expected result, in that order. Null when nothing is needed.
 * `formatDate` / `formatMoney` are injected so this stays pure and testable.
 */
export function bannerFor(
  view: TermView,
  fmt: { date: (iso: string) => string; money: (amount: string, currency: string) => string },
): BannerCopy | null {
  const invoice = view.renewal?.invoice ?? null;
  const owed = invoice ? fmt.money(invoice.total_amount, invoice.currency) : null;
  const ends = view.current_term ? fmt.date(view.current_term.valid_till) : '';

  if (invoice?.pending_claim && (view.state === 'EXPIRING_SOON' || view.state === 'IN_GRACE' || view.state === 'EXPIRED')) {
    return {
      variant: 'info',
      title: 'We are checking your renewal payment',
      body: 'We will confirm by email. Nothing more is needed from you.',
      action: null,
    };
  }

  switch (view.state) {
    case 'EXPIRING_SOON':
      return {
        variant: 'warning',
        title: `Your membership ends on ${ends}`,
        body: owed
          ? `Pay ${owed} by ${fmt.date(invoice!.due_date)} to renew without a break. Your directory listing and member event pricing continue.`
          : 'Your renewal invoice will be ready shortly.',
        action: owed ? { label: 'Renew now', href: MEMBERSHIP_PAGE } : null,
      };
    case 'IN_GRACE':
      return {
        variant: 'warning',
        title: `Your membership expired on ${ends}`,
        body: `Renew by ${view.grace_ends_on ? fmt.date(view.grace_ends_on) : 'the end of the grace period'} to keep your directory listing and member event pricing.${owed ? ` ${owed} outstanding.` : ''}`,
        action: { label: 'Pay now', href: MEMBERSHIP_PAGE },
      };
    case 'EXPIRED':
      return {
        variant: 'danger',
        title: 'Your membership has expired',
        body: 'You are not listed in the member directory and events are charged at the non-member price. Pay your renewal invoice to restore both straight away.',
        action: { label: 'Renew membership', href: MEMBERSHIP_PAGE },
      };
    default:
      return null;
  }
}
```
`scripts/verify-renewal.ts`:
```ts
import assert from 'node:assert/strict';
import { bannerFor } from '../src/components/renewal/renewalCopy';
import type { TermView } from '../src/types/renewal';

const fmt = { date: (iso: string) => iso, money: (a: string, c: string) => `${c} ${a}` };
const base: TermView = {
  state: 'ACTIVE', member_status: 'ACTIVE', today: '2027-03-20', days_left: 11, grace_ends_on: '2027-04-30',
  notice_days: 15, can_change_plan: true,
  current_term: { id: '1', term_type: 'NEW', status: 'ACTIVE', valid_from: '2026-09-12', valid_till: '2027-03-31', plan: null },
  renewal: { term_id: '2', status: 'PENDING_PAYMENT', valid_from: '2027-04-01', valid_till: '2028-03-31', plan_name: 'Best Value',
    invoice: { id: '9', invoice_number: 'IN1', total_amount: '23600.00', currency: 'INR', due_date: '2027-03-31', status: 'ISSUED', pending_claim: false } },
};

assert.equal(bannerFor(base, fmt), null, 'active: no banner');
assert.equal(bannerFor({ ...base, state: 'RENEWED' }, fmt), null, 'renewed: no banner');

const soon = bannerFor({ ...base, state: 'EXPIRING_SOON' }, fmt)!;
assert.equal(soon.variant, 'warning');
assert.match(soon.body, /INR 23600\.00/);
assert.equal(soon.action?.href, '/application/membership');

const grace = bannerFor({ ...base, state: 'IN_GRACE' }, fmt)!;
assert.match(grace.body, /2027-04-30/);

assert.equal(bannerFor({ ...base, state: 'EXPIRED' }, fmt)!.variant, 'danger');

const checking = bannerFor({ ...base, state: 'IN_GRACE', renewal: { ...base.renewal!, invoice: { ...base.renewal!.invoice!, pending_claim: true } } }, fmt)!;
assert.equal(checking.action, null, 'claim pending: no action');

console.log('verify:renewal OK');
```
`package.json` scripts: `"verify:renewal": "tsx scripts/verify-renewal.ts"`.
Run `npm run verify:renewal` → fails (module missing) before `renewalCopy.ts` exists, passes after.

- [ ] **Step 5: Banner component** — `MembershipBanner.tsx`:
```tsx
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';

import { Alert } from '@/components/ui';
import { bannerFor, MEMBERSHIP_PAGE } from '@/components/renewal/renewalCopy';
import RenewalService from '@/services/RenewalService';
import type { TermView } from '@/types/renewal';
import { formatDate } from '@/utils/format';

/**
 * Renewal banner, shown above every member screen while the member's renewal needs them.
 * Silent on failure: the banner is a nudge, never the reason a page fails to render.
 */
export default function MembershipBanner({ formatMoney }: { formatMoney: (amount: string, currency: string) => string }) {
  const pathname = usePathname();
  const [view, setView] = useState<TermView | null>(null);

  useEffect(() => {
    let alive = true;
    RenewalService.getTerm().then((v) => alive && setView(v)).catch(() => undefined);
    return () => { alive = false; };
  }, [pathname]);

  if (!view || pathname === MEMBERSHIP_PAGE) return null;
  const copy = bannerFor(view, { date: formatDate, money: formatMoney });
  if (!copy) return null;

  return (
    <Alert
      variant={copy.variant}
      title={copy.title}
      action={copy.action ? <Link href={copy.action.href}>{copy.action.label}</Link> : undefined}
    >
      {copy.body}
    </Alert>
  );
}
```
`formatMoney`: use the formatter `MoneyText` uses internally (look in `src/utils/format.ts`); export it if it is private. Only if none exists, add to `format.ts`:
```ts
export const formatMoney = (amount: string, currency = 'INR') =>
  new Intl.NumberFormat('en-IN', { style: 'currency', currency }).format(Number(amount));
```
and drop the prop, importing it directly. Check how `Alert`'s `action` expects its element (a `Button`/link) in an existing usage and match it.

In `MemberShell.tsx`, inside `<main id="main" …>` directly above `{children}`: `<div className="mb-4 empty:hidden"><MembershipBanner /></div>` (drop the wrapper margin if the page padding already spaces it). The banner needs the auth token, which `MemberRouteGuard` guarantees for member pages; if `MemberShell` also renders for signed-out states, move the banner inside `MemberArea` under the guard instead.

- [ ] **Step 6: Verify** — `cd customer && npm run typecheck && npm run lint && npm run verify:renewal`.
- [ ] **Step 7: Checkpoint** — stop for the user; do not commit.

---

### Task 14: Customer — membership page (C-18/C-23) and billing copy

**Files:**
- Create: `customer/src/app/(member)/application/membership/page.tsx`, `customer/src/components/renewal/MembershipTermView.tsx`
- Modify: `customer/src/components/billing/InvoiceList.tsx` (:481)

No new rail item (`MEMBER_NAV` is capped at seven): the page lives under "Application & membership" (`match: '/application'` keeps the rail highlighted).

- [ ] **Step 1: Page shell**
```tsx
import type { Metadata } from 'next';
import MembershipTermView from '@/components/renewal/MembershipTermView';

export const metadata: Metadata = { title: 'My membership' };

export default function MembershipPage() {
  return <MembershipTermView />;
}
```
- [ ] **Step 2: `MembershipTermView.tsx`** — client component; load `RenewalService.getTerm()` and `listTerms()` with the same `useState`/`useEffect`/`reload()` pattern as `useMemberRecord.tsx`; `Skeleton` while loading, `ErrorState` (with `onRetry`, `requestId`) on error. Sections, top to bottom:
  1. **Header** — "My membership", one `statusSentence`-style line from `view.state`:
     - `ACTIVE`: "Your membership runs until {valid_till}. We will send your renewal invoice {notice_days} days before it ends."
     - `EXPIRING_SOON` / `IN_GRACE` / `EXPIRED`: reuse `bannerFor(...)` title + body.
     - `RENEWED`: "Your renewal is paid. Your new term starts on {renewal.valid_from}. Nothing more is needed."
     - `AWAITING_FIRST_PAYMENT`: "Your first invoice is waiting on the Application & membership page." with a link to `/application`.
  2. **Current term card** — plan name, cycle, `valid_from – valid_till`, `<StatusChip domain="term" status={current_term.status} />`, "Renews at {renewal_amount + tax}".
  3. **Renewal card** (when `view.renewal`) — invoice number, `MoneyText` total, due date, term dates, chip. When `invoice && !invoice.pending_claim && invoice.status` is ISSUED/PARTIALLY_PAID/OVERDUE: a primary "Pay now" button opening `PaymentClaimDialog` with `amount`, `invoiceNumber`, `consequence="Your renewal is confirmed once we verify the payment. Your membership continues without a break if you pay by the due date."`, `submit={(claim) => MemberService.claimInvoicePayment(invoice.id, claim)}`, `onSubmitted={reload}`. When `pending_claim`: `<Alert variant="info" title="We are checking your payment">We will confirm by email.</Alert>`.
  4. **Change plan (C-23)** — only when `view.can_change_plan`: load `RenewalService.listPlans()`; one radio row per plan (name, cycle, renewal total incl. tax, "Current" badge on `is_current`); a secondary "Switch plan" button, disabled until a different plan is picked; on click a confirm dialog from `@/components/ui` (as used elsewhere in the customer app) reading "Your renewal invoice {n} will be cancelled and a new one issued for {plan} at {total}. The start date stays {renewal.valid_from}."; on confirm `RenewalService.changePlan(id)` → `useToast()` success "Plan changed. Your renewal invoice has been reissued." → `setView(result)` and reload history. A 409 shows inline via `isExpectedConflict` + `Alert`.
  5. **History** — the shared `Table` component exactly as `InvoiceList.tsx` uses it; columns Period (`valid_from – valid_till`), Plan, Type (NEW → "Joined", RENEWAL → "Renewal"), Status (term chip), Invoice. Empty state: "Your terms will be listed here."
- [ ] **Step 3: Billing copy** — `InvoiceList.tsx:481`, make the consequence depend on the invoice kind:
```tsx
consequence={
  target.invoice_type === 'RENEWAL'
    ? 'Your renewal is confirmed once we verify the payment.'
    : 'Membership activates once we confirm the payment.'
}
```
(use the field name the list already uses for the kind — `InvoiceKind` includes `'RENEWAL'`).
- [ ] **Step 4: Verify** — `npm run typecheck && npm run lint && npm run verify:renewal`. In the running customer dev server (do not restart or delete `.next`), sign in as a member with a raised renewal: banner on `/invoices`, not on `/application/membership`; page renders all sections; Pay now opens the claim dialog.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

### Task 15: Self-test — Sentinel `renewal` suite (existing Self-Test Agent)

**Owner:** the existing Self-Test Agent in `sarvadhi-sentinel/`. Do not create a new agent. Follow the structure of an existing suite there (e.g. `billing`), `node run.js --only=renewal`.

Jobs cannot wait 15 days, so the suite drives time through the backend's existing self-test router (`src/routes/selftest/selftest.routes.ts`): Agent B adds `POST /selftest/renewal/run { today: 'YYYY-MM-DD' }` → `runRenewalCycle(new Date(today))`, behind **the same environment guard** the existing self-test routes use (never reachable outside local/test). Add it as part of this task, before the suite.

Assertions (every route in the module gets at least one):
1. Fixture member on a yearly plan ending in 15 days → run → exactly one `RENEWAL` term (`valid_from` = old `valid_till` + 1) and one `RENEWAL` invoice at the plan's renewal price + tax.
2. Run again → still one term, one invoice, one `T-15` reminder row (constraints hold).
3. Financial year basis + quarterly plan crossing 31 March → term ends 31 March, invoice prorated by whole months.
4. Plan with renewal price 0 → no term, no invoice; run summary lists the member as `NO_PRICE`.
5. Admin verifies the renewal claim **before** start → term `PAID_UPCOMING`, member `ACTIVE`; run with `today` = start date → term `ACTIVE`, old term `EXPIRED`, `current_term_id` moved.
6. Unpaid → run with `today` = end + 1 → old term `EXPIRED`, member still `ACTIVE`, admin `grace` bucket count +1 and the member listed in the `grace` list.
7. Run with `today` = end + grace + 1 → member `EXPIRED`, one `membership.expired` notification, directory denies them, `/members/me/invoices` still works.
8. Pay while `EXPIRED` → member `ACTIVE` immediately, term dates unchanged.
9. Plan switch before payment → old invoice + term `CANCELLED`, new term with the same `valid_from`, invoice at the new plan's renewal price; switch while a claim is pending → 409.
10. `GET /admin/renewals/summary` counts equal the three list totals; `limit=500` clamped to 100; member token → 403; `renewal.view` without `renewal.manage` → `POST /run` 403.
11. `GET /membership/me/term` shows the right `state` at each step above.
12. `npm run db:check-comments` → zero rows; `prisma migrate status` → no drift.
13. Don't renew (Tasks 17–18): decline with a raised, unpaid invoice → invoice + renewal term `CANCELLED`, `renewal_declined_at` set; the next two runs raise nothing and send no reminders; member stays `ACTIVE` to the end of the term, sits in grace, then `EXPIRED`; decline while `PAID_UPCOMING` or with a claim pending → 409; "Renew after all" after expiry → invoice raised at once, paying it → member `ACTIVE`; admin row shows Declined.

Then drive both UIs in a browser and attach screenshots: admin `/renewals` (three tabs, Generate Invoices toast), customer banner in grace, `/application/membership` with Pay now and Switch plan. Report to `sarvadhi-sentinel/reports/` with Blocker/Major/Minor severities; Blockers and Majors go back to the owning agent, then the **full** suite re-runs.

---

### Task 16: Docs

**Files:** `docs/api-specification.md` (§M6, :94–103), `docs/notification-architecture.md` (:58), `docs/implementation-status.md` (M6 row), `docs/screen-inventory.md` (C-18 states).

- [ ] Replace the M6 endpoint table with the Task 8 and Task 11 contracts (drop `POST /membership/me/renew`, `POST /admin/renewals/:memberId/initiate`, `POST /admin/renewals/:termId/extend-grace`; add `/membership/me/renewal/plans`, `POST /membership/me/renewal/plan`, `GET /admin/renewals/summary`, `POST /admin/renewals/run`).
- [ ] Add `POST /membership/me/renewal/decline` and `POST /membership/me/renewal/resume` (Task 17) to the M6 endpoint table.
- [ ] `membership.renewal_reminder` schedule → `T-15/T-7/T-3/T-0`; add `membership.expired` channels EMAIL + IN_APP.
- [ ] C-18 states → `active, expiring soon, paid/renews on, in grace, expired`; route `/application/membership`.
- [ ] M6 status → `IN_PROGRESS` while tasks run, `SELF_TEST` at Task 15; add a change-log row at the end.
- [ ] Checkpoint — stop for the user; do not commit.

---

### Task 17: "Don't renew" — backend + admin

**Decided 2026-09-10:** the member can press "I don't want to renew". The renewal invoice is cancelled and reminders stop; they keep access until the term ends, then grace and `EXPIRED` as normal; they can still come back later.

**Rulings carried into this task (controller):**
- A cancelled renewal term is invisible to `dueCandidates` (`status <> 'CANCELLED'`), so without a stored decision the hourly job would bill the member again. The decision is stored on the **current** term as `renewal_declined_at`; the job skips such terms.
- "Can still come back later" needs a way back once the invoice is cancelled: **"Renew after all"** clears the flag and, if the term ends within the notice window (or has already ended, member `ACTIVE` or `EXPIRED`), raises the renewal at once so there is something to pay.
- Decline is allowed with or without a raised invoice, while the member is `ACTIVE`, the current term is `ACTIVE`/`EXPIRED`, no paid next term exists, and no payment claim is pending on the renewal invoice.

**Files:**
- Modify: `backend/prisma/schema/application.prisma` (`MembershipTerm`)
- Create: `backend/prisma/migrations/20260910090200_m6_renewal_decline/migration.sql`
- Modify: `backend/src/constant/audit.constant.ts`, `backend/src/locales/en.json`
- Modify: `backend/src/modules/renewal/renewal.state.ts` (+ test), `renewal.repository.ts`, `renewal.admin.service.ts`, `renewal.member.service.ts` (+ test), `renewal.controller.ts`, `renewal.routes.ts`
- Modify: `admin/src/services/renewalsService.ts`, `admin/src/pages/renewals/Renewals.tsx`

**Interfaces:**
- Produces: `MembershipTerm.renewal_declined_at: Date | null`; `TermState` gains `'DECLINED'`; `termState` input gains `declined: boolean`; `TermView` gains `renewal_declined: boolean; can_decline: boolean; can_resume: boolean`; `RenewalRow` gains `renewal_declined: boolean`; `POST /api/v1/membership/me/renewal/decline` → `TermView` (409 `renewal.cannotDecline`); `POST /api/v1/membership/me/renewal/resume` → `TermView` (409 `renewal.notDeclined`, 409 `renewal.planNotAvailable`).

- [ ] **Step 1: Schema + migration**

In `model MembershipTerm`:
```prisma
  /// When the member said they will not renew after this term. The renewal job raises nothing
  /// for a term with this set; "renew after all" clears it. NULL means no decision was made.
  renewal_declined_at DateTime? @db.Timestamptz(6)
```
`prisma/migrations/20260910090200_m6_renewal_decline/migration.sql`:
```sql
-- M6 — "Don't renew" (decided 2026-09-10). Stored on the term being left, so the hourly
-- renewal job can tell "not raised yet" from "the member said no".
ALTER TABLE "MembershipTerms" ADD COLUMN "renewal_declined_at" TIMESTAMPTZ(6);

COMMENT ON COLUMN "MembershipTerms"."renewal_declined_at" IS 'When the member said they will not renew after this term. The renewal job raises nothing for a term with this set; "renew after all" clears it. NULL means no decision was made.';
```
Run `npx prisma migrate dev && npx prisma generate && npm run db:check-comments` (zero rows).

- [ ] **Step 2: Constants + messages** — `AUDIT_ACTIONS`: `RENEWAL_DECLINED: 'renewal.declined'`, `RENEWAL_RESUMED: 'renewal.resumed'`. `en.json` `renewal`:
```json
    "declined": "You have chosen not to renew",
    "resumed": "Renewal restarted",
    "cannotDecline": "This renewal is already paid or being checked, so it can't be declined",
    "notDeclined": "There is no declined renewal to restart"
```

- [ ] **Step 3: `termState` (TDD)** — add to `renewal.state.test.ts`: put `declined: false` in `base`, and
```ts
  it('is DECLINED when the member said no and has not yet expired', () => {
    expect(termState({ ...base, declined: true, memberStatus: 'ACTIVE', current: current('2027-03-31'), renewalStatus: null })).toBe('DECLINED');
  });
  it('is EXPIRED, not DECLINED, once grace has passed', () => {
    expect(termState({ ...base, declined: true, memberStatus: 'EXPIRED', current: { status: 'EXPIRED', valid_till: day('2027-01-31') }, renewalStatus: null })).toBe('EXPIRED');
  });
```
Run → FAIL. Then in `renewal.state.ts`: add `| 'DECLINED'` to `TermState`, `declined: boolean` to the input, destructure it, and insert directly after `if (memberStatus === 'EXPIRED') return 'EXPIRED';`:
```ts
  if (declined) return 'DECLINED';
```
Pass `declined: Boolean(current?.renewal_declined_at)` from `getMyTermView` (select `renewal_declined_at` on `current_term`). Run → PASS.

- [ ] **Step 4: Job + buckets skip / show declined** — in `renewal.repository.ts`:
  - `dueCandidates`: add `AND t.renewal_declined_at IS NULL` after `AND t.valid_till <= ${isoDay(horizon)}::date`.
  - `bucketBase`: select `t.renewal_declined_at` in `cur`; `bucketRows`: select `(cur.renewal_declined_at IS NOT NULL) AS renewal_declined`; add `renewal_declined: boolean` to `BucketRow`; map it in `listBucket`.

- [ ] **Step 5: Member service (TDD)** — add to `renewal.member.service.test.ts` (same mocks; add `update` already present on `membershipTerm`):
```ts
describe('declineRenewal', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    memberFindFirst.mockResolvedValue({ status: 'ACTIVE', current_term: { id: 10n, status: 'ACTIVE', valid_till: day('2027-03-31'), renewal_declined_at: null } });
  });

  it('cancels a raised, unpaid renewal and records the decision on the current term', async () => {
    termFindFirst.mockResolvedValue(pending());
    await service.declineRenewal(5n, AUDIT);
    expect(invoiceUpdate).toHaveBeenCalledWith({ where: { id: 30n }, data: { status: 'CANCELLED' } });
    expect(termUpdate).toHaveBeenCalledWith({ where: { id: 20n }, data: { status: 'CANCELLED' } });
    expect(termUpdate).toHaveBeenCalledWith({ where: { id: 10n }, data: { renewal_declined_at: expect.any(Date) } });
  });

  it('records the decision when no invoice has been raised yet', async () => {
    termFindFirst.mockResolvedValue(null);
    await service.declineRenewal(5n, AUDIT);
    expect(invoiceUpdate).not.toHaveBeenCalled();
    expect(termUpdate).toHaveBeenCalledWith({ where: { id: 10n }, data: { renewal_declined_at: expect.any(Date) } });
  });

  it('refuses once the renewal is paid', async () => {
    termFindFirst.mockResolvedValue(pending({ status: 'PAID_UPCOMING' }));
    await expect(service.declineRenewal(5n, AUDIT)).rejects.toMatchObject({ messageKey: 'renewal.cannotDecline' });
  });
});

describe('resumeRenewal', () => {
  beforeEach(() => vi.clearAllMocks());

  it('clears the decision and raises the renewal when the term ends inside the window', async () => {
    memberFindFirst.mockResolvedValue({ status: 'EXPIRED', current_term: { id: 10n, valid_till: day('2026-01-31'), category_id: 2n, tier_id: null, fee_plan_id: 7n, renewal_declined_at: new Date() } });
    raiseRenewal.mockResolvedValue({ outcome: 'RAISED', termId: 21n, invoiceId: 31n, invoiceNumber: 'IN3', total: '23600.00' });
    await service.resumeRenewal(5n, AUDIT);
    expect(termUpdate).toHaveBeenCalledWith({ where: { id: 10n }, data: { renewal_declined_at: null } });
    expect(raiseRenewal.mock.calls[0][1]).toMatchObject({ memberId: 5n, feePlanId: 7n });
  });

  it('refuses when nothing was declined', async () => {
    memberFindFirst.mockResolvedValue({ status: 'ACTIVE', current_term: { id: 10n, valid_till: day('2027-03-31'), category_id: 2n, tier_id: null, fee_plan_id: 7n, renewal_declined_at: null } });
    await expect(service.resumeRenewal(5n, AUDIT)).rejects.toMatchObject({ messageKey: 'renewal.notDeclined' });
  });
});
```
Run → FAIL. Implement in `renewal.member.service.ts` (reusing its `nextTerm`, `SWITCHABLE_INVOICE`, `conflict`, the lock statement, `writeAudit` shape from `switchRenewalPlan`):
```ts
type AuditActor = { actorId: bigint; ip: string | null; userAgent: string | null; requestId: string | null };
const OPEN_TERM: TermStatus[] = [TermStatus.ACTIVE, TermStatus.EXPIRED];

/** "I don't want to renew" (decided 2026-09-10). Access continues to the end of the term, then grace. */
export const declineRenewal = async (memberId: bigint, audit: AuditActor) => {
  await prisma.$transaction(async (tx) => {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext('membership.renewal'), (${memberId} % 2147483647)::int)`;

    const member = await tx.member.findFirst({
      where: { id: memberId },
      select: { status: true, current_term: { select: { id: true, status: true, valid_till: true, renewal_declined_at: true } } },
    });
    const current = member?.current_term;
    if (!member || member.status !== 'ACTIVE' || !current || !OPEN_TERM.includes(current.status)) {
      throw conflict('renewal.cannotDecline');
    }
    if (current.renewal_declined_at) return; // already declined — pressing twice is not an error

    const next = await nextTerm(tx, memberId, current.valid_till);
    if (next) {
      const invoice = next.invoice;
      if (
        next.status !== TermStatus.PENDING_PAYMENT ||
        !invoice ||
        !SWITCHABLE_INVOICE.includes(invoice.status) ||
        invoice.paymentSubmissions.length > 0
      ) {
        throw conflict('renewal.cannotDecline');
      }
      await tx.invoice.update({ where: { id: invoice.id }, data: { status: InvoiceStatus.CANCELLED } });
      await tx.membershipTerm.update({ where: { id: next.id }, data: { status: TermStatus.CANCELLED } });
      await writeAudit(tx, {
        actorType: ACTOR_TYPES.MEMBER, ...audit,
        action: AUDIT_ACTIONS.INVOICE_CANCELLED, entityName: 'Invoices', entityId: invoice.id,
        before: { status: invoice.status }, after: { status: InvoiceStatus.CANCELLED, reason: 'Member declined renewal' },
      });
    }

    const at = new Date();
    await tx.membershipTerm.update({ where: { id: current.id }, data: { renewal_declined_at: at } });
    await writeAudit(tx, {
      actorType: ACTOR_TYPES.MEMBER, ...audit,
      action: AUDIT_ACTIONS.RENEWAL_DECLINED, entityName: 'MembershipTerms', entityId: current.id,
      before: { renewal_declined_at: null }, after: { renewal_declined_at: at.toISOString() },
    });
  });

  return getMyTermView(memberId);
};

/** "Renew after all": undo the decision; bill now if the term ends inside the window or has ended. */
export const resumeRenewal = async (memberId: bigint, audit: AuditActor) => {
  const today = dbToday();
  const basis = ((await getSetting(SETTING_KEYS.RENEWAL_BASIS)) ?? 'term') as RenewalBasis;
  const noticeDays = await getNumericSetting(SETTING_KEYS.RENEWAL_NOTICE_DAYS, 15);
  const dueDays = await getNumericSetting(SETTING_KEYS.INVOICE_DUE_DAYS, 15);

  await prisma.$transaction(async (tx) => {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext('membership.renewal'), (${memberId} % 2147483647)::int)`;

    const member = await tx.member.findFirst({
      where: { id: memberId },
      select: {
        status: true,
        current_term: { select: { id: true, valid_till: true, category_id: true, tier_id: true, fee_plan_id: true, renewal_declined_at: true } },
      },
    });
    const current = member?.current_term;
    if (!member || !current?.renewal_declined_at || !['ACTIVE', 'EXPIRED'].includes(member.status)) {
      throw conflict('renewal.notDeclined');
    }

    await tx.membershipTerm.update({ where: { id: current.id }, data: { renewal_declined_at: null } });
    await writeAudit(tx, {
      actorType: ACTOR_TYPES.MEMBER, ...audit,
      action: AUDIT_ACTIONS.RENEWAL_RESUMED, entityName: 'MembershipTerms', entityId: current.id,
      before: { renewal_declined_at: current.renewal_declined_at.toISOString() }, after: { renewal_declined_at: null },
    });

    if (current.valid_till <= addDays(today, noticeDays)) {
      const result = await raiseRenewal(
        tx,
        { memberId, categoryId: current.category_id, tierId: current.tier_id, feePlanId: current.fee_plan_id, previousValidTill: current.valid_till },
        { today, basis, dueDays },
      );
      if (result.outcome === 'SKIPPED' && result.reason !== 'ALREADY_RAISED') throw conflict('renewal.planNotAvailable');
    }
  });

  return getMyTermView(memberId);
};
```
In `getMyTermView` add to the returned object:
```ts
    renewal_declined: Boolean(current?.renewal_declined_at),
    can_decline:
      member.status === 'ACTIVE' && !!current && OPEN_TERM.includes(current.status) && !current.renewal_declined_at &&
      (!next || (next.status === TermStatus.PENDING_PAYMENT && invoice !== null && SWITCHABLE_INVOICE.includes(invoice.status) && !pendingClaim)),
    can_resume: Boolean(current?.renewal_declined_at) && ['ACTIVE', 'EXPIRED'].includes(member.status),
```
Run → PASS.

- [ ] **Step 6: Routes + controller** — `renewalMemberRouter.post('/me/renewal/decline', controller.declineMyRenewal)` and `.post('/me/renewal/resume', controller.resumeMyRenewal)`; handlers built like `switchMyRenewalPlan` (same `audit` object), `RES_STATUS.ACTION`, message keys `renewal.declined` / `renewal.resumed`.

- [ ] **Step 7: Admin** — `RenewalRow` gains `renewal_declined: boolean`; in `Renewals.tsx` Status column render, first branch: `row.renewal_declined ? <Badge tone="neutral">Declined</Badge> : …existing branches`.

- [ ] **Step 8: Verify** — backend `npm test && npm run typecheck && npm run lint`; admin `npm run typecheck && npm run lint`.
- [ ] **Step 9: Checkpoint** — stop for the user; do not commit.

---

### Task 18: "Don't renew" — customer

**Files:** `customer/src/types/renewal.ts`, `customer/src/services/RenewalService.ts`, `customer/src/constants/endpoints.ts`, `customer/src/components/renewal/renewalCopy.ts`, `customer/scripts/verify-renewal.ts`, `customer/src/components/renewal/MembershipTermView.tsx`

**Interfaces:** consumes Task 17 (`TermView.renewal_declined | can_decline | can_resume`, `'DECLINED'` state, the two POST routes).

- [ ] **Step 1: Types, endpoints, service** — add `'DECLINED'` to `TermState`; `renewal_declined: boolean; can_decline: boolean; can_resume: boolean` to `TermView` and to `normaliseTermView` (default `false`). Endpoints `renewalDecline: '/membership/me/renewal/decline'`, `renewalResume: '/membership/me/renewal/resume'`. Service:
```ts
  async decline(): Promise<TermView> {
    return normaliseTermView((await ApiService.post<unknown>(ENDPOINTS.renewalDecline, {})).data);
  },
  async resume(): Promise<TermView> {
    return normaliseTermView((await ApiService.post<unknown>(ENDPOINTS.renewalResume, {})).data);
  },
```
- [ ] **Step 2: Copy (TDD via verify script)** — add to `verify-renewal.ts` (add the three new fields, all `false`, to `base`):
```ts
const declined = bannerFor({ ...base, state: 'DECLINED', renewal: null, renewal_declined: true, can_resume: true }, fmt)!;
assert.equal(declined.variant, 'info');
assert.match(declined.body, /2027-03-31/);
assert.equal(declined.action?.label, 'Renew after all');
```
Run `npm run verify:renewal` → FAIL. Add to `bannerFor` switch:
```ts
    case 'DECLINED':
      return {
        variant: 'info',
        title: 'You chose not to renew',
        body: `Your membership ends on ${ends}. After the grace period you leave the member directory and member event pricing. You can change your mind at any time.`,
        action: { label: 'Renew after all', href: MEMBERSHIP_PAGE },
      };
```
Run → PASS.
- [ ] **Step 3: Membership page** — in `MembershipTermView.tsx`:
  - Header sentence for `DECLINED` = the banner title + body.
  - When `view.can_decline`: a secondary (not primary) "I don't want to renew" button below the renewal card. Confirm dialog: title "Stop your renewal?", body "`{invoice ? `Invoice ${invoice.invoice_number} will be cancelled and reminders stop. ` : 'We will not send a renewal invoice. '}`Your membership stays active until {valid_till}, then a grace period until {grace_ends_on}, then it expires. You can renew again at any time.", confirm label "Stop renewal" → `RenewalService.decline()` → toast "You have chosen not to renew." → `setView(result)`.
  - When `view.can_resume`: a primary "Renew after all" button → `RenewalService.resume()` → toast "Renewal restarted." → `setView(result)`; if the result has a renewal invoice, the Pay now section appears as in Task 14.
  - 409s show inline via `isExpectedConflict` + `Alert`, as for plan switch.
- [ ] **Step 4: Verify** — `npm run typecheck && npm run lint && npm run verify:renewal`.
- [ ] **Step 5: Checkpoint** — stop for the user; do not commit.

---

## Choices made in this plan (flag to the user)

These fill gaps the decisions did not cover. Each is easy to change:
1. **Hourly job**, not nightly: idempotent by constraint, and it avoids a UTC-vs-local day boundary.
2. **Reminders skip an invoice with a pending payment claim**: a member who has told us they paid is not nagged.
3. **A late-raised invoice gets only today's reminder stage** (no burst of missed stages).
4. **Plan switch prices the new plan's renewal price** (not its joining price), from the same start date.
5. **A term with no plan on record (pre-fee-plans legacy) is not billed**: it is reported as "no plan on record" in the Generate Invoices result for the office to handle.
6. **Member page lives at `/application/membership`**, not a new rail item (the rail is capped at seven).
