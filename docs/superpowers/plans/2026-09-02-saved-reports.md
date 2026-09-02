# Saved Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the four reports from a live table into saved records that are generated once, listed, and downloadable again later.

**Architecture:** A `GeneratedReports` row stores the result of running one of the four existing report queries, together with the filters that produced it as `{id, name}` pairs. The screen becomes a list of past reports with a generate drawer. The existing column registry stays the single source of truth for columns, so the Excel and the screen still cannot drift.

**Tech Stack:** Node + Express + TypeScript · Prisma + PostgreSQL · Zod · ExcelJS · React + TypeScript + Ant Design (admin) · Vitest

**Spec:** `docs/specs/2026-09-02-saved-reports.md`

## Global Constraints

- **Never run `git commit` without the user's explicit go-ahead.** The commit step at the end of each task means *stage and ask*, not commit.
- Business logic lives in the backend. Any figure computed in a frontend is a review failure.
- Money crosses the wire as a 2-decimal **string**, never a JSON number (ADR-007).
- Ids cross the wire as **strings** — the columns are bigint and JSON numbers lose precision past 2^53.
- Exports are **.xlsx only**, never CSV, and always through `helpers/excel.ts`.
- Admin screens are assembled from `@/components/ui` only. A page may import from `antd` **only** `Form`, `Form.Item`, `Input`, `Input.TextArea`, `Switch`, `DatePicker`, `Segmented`, `Tooltip`. No page sets a colour, radius, height or font-size.
- Prisma migrations only. Never edit an applied migration. Every new column carries a `///` doc comment — `npm run db:check-comments` enforces it.
- Tests are Vitest unit tests that mock `@db/prisma`. Follow `src/modules/masters/masters.checklist.test.ts`.
- Run from `backend/`: `npx vitest run <path>`, `npm run lint`, `npx tsc --noEmit -p tsconfig.json`.
  Backend typecheck has **54 pre-existing errors** in test files. That count must not increase.
- Run from `admin/`: `npm run typecheck`, `npm run lint`.
- Do not kill or restart the user's dev servers, and do not delete `dist/` or `.next/`.

---

## File Structure

**Backend — modified**
- `prisma/schema/system.prisma` — add the `GeneratedReport` model beside `AuditLog` and `SystemSetting`
- `prisma/seed/permissions.ts` — add `report.create`
- `prisma/seed/roles.ts` — grant it to SUPER_ADMIN, ADMIN, ACCOUNTS
- `src/modules/report/report.types.ts` — filter refs, generate schema, list schema
- `src/modules/report/report.repository.ts` — member/event filters on the four queries, plus CRUD on `GeneratedReports`
- `src/modules/report/report.service.ts` — the registry gains `summarise` and `filterKeys`; generate/list/get/build-file replace run/export
- `src/modules/report/report.controller.ts` — new endpoint set
- `src/modules/report/report.routes.ts` — new endpoint set
- `src/jobs/definitions.ts` — the prune job
- `src/constant/audit.constant.ts` — `REPORT_GENERATED`

**Backend — created**
- `prisma/migrations/<stamp>_m10_generated_reports/migration.sql`
- `src/modules/report/report.generate.test.ts`
- `src/modules/report/report.filters.test.ts`
- `src/modules/report/report.export.test.ts`

**Admin — modified**
- `src/constant/endpoints.ts` — the report endpoint set
- `src/services/reportsService.ts` — generate/list/get/download
- `src/pages/reports/Reports.tsx` — becomes the list screen

**Admin — created**
- `src/pages/reports/GenerateReportDrawer.tsx`
- `src/pages/reports/ReportSummaryDrawer.tsx`
- `src/pages/reports/reportSpecs.ts` — the card definitions and per-report filter fields

---

### Task 1: The `GeneratedReports` table

**Files:**
- Modify: `backend/prisma/schema/system.prisma`
- Create: `backend/prisma/migrations/<stamp>_m10_generated_reports/migration.sql`

**Interfaces:**
- Consumes: nothing
- Produces: Prisma model `GeneratedReport`, table `GeneratedReports`, accessible as `prisma.generatedReport`

- [ ] **Step 1: Add the model to the schema**

Append to `backend/prisma/schema/system.prisma`:

```prisma
/// One report that somebody ran. The result is stored, not recomputed: a report is a
/// historical record, and the whole point of saving it is that it still says the same
/// thing next month.
model GeneratedReport {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// Which of the four reports this is: members, revenue, renewals, events.
  report_type String @db.VarChar(40)

  /// What the person called it. Suggested from the filters, editable before generating.
  report_name String @db.VarChar(200)

  /// Lower bound of the report's date range, or NULL when it takes none.
  from_date DateTime? @db.Date

  /// Upper bound, inclusive whole day.
  to_date DateTime? @db.Date

  /// The filters that produced this result, as {id, name} pairs per filter key. Names are
  /// stored beside ids deliberately: an id-only filter becomes unreadable the moment a
  /// category or a company is renamed, and the saved numbers stop being explainable.
  filters Json @default("{}")

  /// Whether the row-level breakdown was collected. Decides whether the download carries a
  /// Detail sheet.
  include_details Boolean @default(false)

  /// The frozen result: { summary: {...}, detail: [...] | null, row_count: n }.
  report_data Json @default("{}")

  /// queued, running, ready or failed. Only `ready` and `failed` are written today; the
  /// other two are in the constraint from the start because adding a value to a CHECK
  /// later is a migration, and background generation is a decided future.
  status String @default("ready") @db.VarChar(20)

  /// How many detail rows matched, whether or not they were stored.
  row_count BigInt @default(0)

  /// Why it failed, for a `failed` row. NULL otherwise.
  error_message String? @db.Text

  /// AdminUsers.id. ON DELETE RESTRICT: a report must never lose the person who ran it.
  generated_by BigInt

  /// Row creation timestamp (UTC) — when the report was run.
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// The staff member who ran it.
  admin_user AdminUser @relation(fields: [generated_by], references: [id], onDelete: Restrict, onUpdate: Cascade)

  @@index([report_type, createdAt(sort: Desc)])
  @@index([generated_by, createdAt(sort: Desc)])
  @@index([createdAt(sort: Desc)])
  @@map("GeneratedReports")
}
```

Add the back-relation to `AdminUser` in `backend/prisma/schema/identity.prisma`, beside its other relation fields:

```prisma
  /// Reports this staff member generated.
  generated_reports GeneratedReport[]
```

- [ ] **Step 2: Create the migration without applying it**

Run: `cd backend && npx prisma migrate dev --create-only --name m10_generated_reports`
Expected: a new folder under `prisma/migrations/` containing `migration.sql`.

- [ ] **Step 3: Add the CHECK constraints Prisma cannot express**

Append to the generated `migration.sql`:

```sql
-- The four reports this platform has. A fifth is a migration, deliberately: a typo'd
-- report_type would otherwise sit in the table and produce an empty download.
ALTER TABLE "GeneratedReports" ADD CONSTRAINT "GeneratedReports_report_type_check"
  CHECK ("report_type" IN ('members', 'revenue', 'renewals', 'events'));

-- queued and running are unreachable today. They are in the constraint from the start
-- because adding a value to a CHECK later is a second migration against the same table.
ALTER TABLE "GeneratedReports" ADD CONSTRAINT "GeneratedReports_status_check"
  CHECK ("status" IN ('queued', 'running', 'ready', 'failed'));
```

- [ ] **Step 4: Apply it and regenerate the client**

Run: `cd backend && npx prisma migrate dev && npm run prisma:generate`
Expected: migration applied, client regenerated.

- [ ] **Step 5: Verify the column comments are present**

Run: `cd backend && npm run db:check-comments`
Expected: PASS. If it names a column, the `///` comment above that field is missing.

- [ ] **Step 6: Stage and ask before committing**

```bash
git -C backend add prisma/schema prisma/migrations
# then ASK the user before running git commit
```

---

### Task 2: The `report.create` permission

**Files:**
- Modify: `backend/prisma/seed/permissions.ts:71-72`
- Modify: `backend/prisma/seed/roles.ts:75-76,123-124`

**Interfaces:**
- Consumes: nothing
- Produces: permission code `report.create`, granted to SUPER_ADMIN, ADMIN, ACCOUNTS

- [ ] **Step 1: Add the permission**

In `permissions.ts`, beside the two existing report rows:

```ts
  { code: 'report.view', description: 'View reports.' },
  { code: 'report.create', description: 'Generate a new report.' },
  { code: 'report.export', description: 'Export reports.' },
```

- [ ] **Step 2: Grant it to the roles that already hold `report.view`**

In `roles.ts`, add `'report.create'` next to `'report.view'` in **both** places it appears (lines ~75 and ~123).

- [ ] **Step 3: Re-seed**

Run: `cd backend && npm run prisma:seed`
Expected: completes without error. Seeds are idempotent.

- [ ] **Step 4: Verify the grant landed**

Run:
```bash
cd backend && npx tsx -e "
import { prisma } from './src/db/prisma';
prisma.\$queryRawUnsafe(\`SELECT r.code AS role, p.code AS perm FROM \\\"RolePermissions\\\" rp
  JOIN \\\"Roles\\\" r ON r.id = rp.role_id JOIN \\\"Permissions\\\" p ON p.id = rp.permission_id
  WHERE p.code = 'report.create' ORDER BY r.code\`).then((r) => { console.log(r); process.exit(0); });
"
```
Expected: three rows — SUPER_ADMIN, ADMIN, ACCOUNTS.

- [ ] **Step 5: Stage and ask before committing**

```bash
git -C backend add prisma/seed
# then ASK the user before running git commit
```

---

### Task 3: Filter refs and the member / event filters

**Files:**
- Modify: `backend/src/modules/report/report.types.ts`
- Modify: `backend/src/modules/report/report.repository.ts`
- Create: `backend/src/modules/report/report.filters.test.ts`

**Interfaces:**
- Consumes: `ReportType`, `ReportParams` from Task 0 (already in the repo)
- Produces:
  - `interface FilterRef { id: string; name: string }`
  - `type ReportFilters = Record<string, FilterRef[]>`
  - `const REPORT_FILTER_KEYS: Record<ReportType, readonly string[]>`
  - `const filterRefSchema: ZodType<FilterRef>`
  - `toRepoParams(type: ReportType, filters: ReportFilters, from?: string, to?: string): ReportParams`
  - `ReportParams` gains `memberIds?: string[]` and `eventIds?: string[]`

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/report/report.filters.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { REPORT_FILTER_KEYS, toRepoParams } from '@modules/report/report.types';

describe('REPORT_FILTER_KEYS', () => {
  it('gives every report exactly the filters it reads', () => {
    expect(REPORT_FILTER_KEYS.members).toEqual([
      'status', 'category_id', 'city', 'state', 'member_id',
    ]);
    expect(REPORT_FILTER_KEYS.revenue).toEqual(['invoice_type', 'member_id']);
    expect(REPORT_FILTER_KEYS.renewals).toEqual(['status', 'member_id']);
    expect(REPORT_FILTER_KEYS.events).toEqual(['event_id']);
  });

  /* Events narrows by event, not by member: "which events did this member attend"
     is a different report from "how did these events do". */
  it('does not offer a member filter on the events report', () => {
    expect(REPORT_FILTER_KEYS.events).not.toContain('member_id');
  });
});

describe('toRepoParams', () => {
  it('turns stored refs into the id lists the queries take', () => {
    const params = toRepoParams('members', {
      status: [{ id: 'ACTIVE', name: 'Active' }],
      member_id: [
        { id: '142', name: 'ABC Textiles' },
        { id: '87', name: 'XYZ Exports' },
      ],
    });

    expect(params.statuses).toEqual(['ACTIVE']);
    expect(params.memberIds).toEqual(['142', '87']);
  });

  /* An empty selection is no filter at all, never "match nothing". */
  it('drops an empty selection rather than sending an empty list', () => {
    const params = toRepoParams('members', { status: [] });

    expect(params.statuses).toBeUndefined();
  });

  it('carries the date range through', () => {
    const params = toRepoParams('revenue', {}, '2026-08-01', '2026-08-31');

    expect(params.from).toBe('2026-08-01');
    expect(params.to).toBe('2026-08-31');
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run src/modules/report/report.filters.test.ts`
Expected: FAIL — `REPORT_FILTER_KEYS` and `toRepoParams` are not exported.

- [ ] **Step 3: Add the types and the mapper**

In `report.types.ts`, replace the existing `reportQuerySchema` block with:

```ts
/**
 * A filter selection carries the display name beside the id, on purpose.
 *
 * A report is a historical record. If a category is renamed or a company
 * terminated six months from now, an id-only filter becomes unreadable and the
 * saved numbers stop being explainable — you are left with a total and no way
 * to say what it counted. The name costs a few bytes and keeps the report
 * honest.
 */
export const filterRefSchema = z.object({
  id: z.string().trim().min(1).max(60),
  name: z.string().trim().min(1).max(200),
});

export type FilterRef = z.infer<typeof filterRefSchema>;

export type ReportFilters = Record<string, FilterRef[]>;

/**
 * Which filter keys each report accepts — one source of truth, read by the
 * generate schema's validation here and mirrored by the drawer.
 */
export const REPORT_FILTER_KEYS = {
  members: ['status', 'category_id', 'city', 'state', 'member_id'],
  revenue: ['invoice_type', 'member_id'],
  renewals: ['status', 'member_id'],
  events: ['event_id'],
} as const satisfies Record<ReportType, readonly string[]>;

/** The stored refs, as the four queries want them. */
export const toRepoParams = (
  type: ReportType,
  filters: ReportFilters,
  from?: string,
  to?: string,
): RepoParams => {
  // An empty selection is no filter at all, never "match nothing".
  const ids = (key: string): string[] | undefined => {
    const refs = filters[key];

    return refs && refs.length > 0 ? refs.map((ref) => ref.id) : undefined;
  };

  const params: RepoParams = {};

  if (ids('status')) params.statuses = ids('status');
  if (ids('category_id')) params.categoryIds = ids('category_id');
  if (ids('city')) params.cities = ids('city');
  if (ids('state')) params.states = ids('state');
  if (ids('invoice_type')) params.invoiceTypes = ids('invoice_type');
  if (ids('member_id')) params.memberIds = ids('member_id');
  if (ids('event_id')) params.eventIds = ids('event_id');
  if (from) params.from = from;
  if (to) params.to = to;

  void type;

  return params;
};
```

Add at the top of `report.types.ts`:

```ts
import type { ReportParams as RepoParams } from '@modules/report/report.repository';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd backend && npx vitest run src/modules/report/report.filters.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Add the two new params to the repository interface**

In `report.repository.ts`, extend `ReportParams`:

```ts
  /** Specific companies. Empty or absent means every company. */
  memberIds?: string[];
  /** Specific events. */
  eventIds?: string[];
```

- [ ] **Step 6: Apply the member filter to three queries**

In `members`, add beside the other prepared values:

```ts
  const memberIds = params.memberIds?.length ? params.memberIds : null;
```

and inside its `WHERE`:

```sql
       AND (${memberIds}::bigint[] IS NULL OR m."id" = ANY(${memberIds}::bigint[]))
```

In `revenue`, add the same prepared value and, in its `WHERE`:

```sql
       AND (${memberIds}::bigint[] IS NULL OR i."member_id" = ANY(${memberIds}::bigint[]))
```

In `renewals`, the same prepared value and:

```sql
       AND (${memberIds}::bigint[] IS NULL OR m."id" = ANY(${memberIds}::bigint[]))
```

- [ ] **Step 7: Apply the event filter**

In `events`, add:

```ts
  const eventIds = params.eventIds?.length ? params.eventIds : null;
```

and in its `WHERE`:

```sql
       AND (${eventIds}::bigint[] IS NULL OR e."id" = ANY(${eventIds}::bigint[]))
```

- [ ] **Step 8: Verify against the real database**

Run:
```bash
cd backend && cat > src/__probe.ts <<'EOF'
import { members, revenue, renewals, events } from '@modules/report/report.repository';
import { prisma } from '@db/prisma';
const main = async () => {
  const all = await members(prisma, {});
  const one = await members(prisma, { memberIds: [String(1)] });
  console.log('members all:', all.total, '| filtered to id 1:', one.total);
  console.log('revenue by member 1:', (await revenue(prisma, { memberIds: ['1'] })).total);
  console.log('renewals by member 1:', (await renewals(prisma, { memberIds: ['1'] })).total);
  console.log('events by event 1:', (await events(prisma, { eventIds: ['1'] })).total);
};
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
EOF
npx tsx src/__probe.ts; rm -f src/__probe.ts
```
Expected: the filtered counts are **lower than or equal to** the unfiltered ones, and nothing throws.

- [ ] **Step 9: Lint, typecheck, stage**

Run: `cd backend && npm run lint && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"`
Expected: lint clean, error count still **54**.

```bash
git -C backend add src/modules/report
# then ASK the user before running git commit
```

---

### Task 4: Generate a report

**Files:**
- Modify: `backend/src/modules/report/report.types.ts`
- Modify: `backend/src/modules/report/report.service.ts`
- Modify: `backend/src/modules/report/report.repository.ts`
- Modify: `backend/src/constant/audit.constant.ts`
- Create: `backend/src/modules/report/report.generate.test.ts`

**Interfaces:**
- Consumes: `REPORT_FILTER_KEYS`, `toRepoParams`, `FilterRef` (Task 3)
- Produces:
  - `generateReportSchema` — Zod body schema
  - `EXCEL_MAX_ROWS = 1_048_576`
  - `summarise(type: ReportType, rows: ReportRow[]): Record<string, string | number>`
  - `generateReport(input: GenerateReportInput, actor: { id: bigint; ip: string | null; userAgent: string | null; requestId: string | null }): Promise<GeneratedReportDto>`
  - `insertGeneratedReport(db, …)` in the repository
  - `AUDIT_ACTIONS.REPORT_GENERATED = 'report.generated'`

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/report/report.generate.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { generateReportSchema } from '@modules/report/report.types';
import { summarise } from '@modules/report/report.service';

describe('generateReportSchema', () => {
  const base = { report_type: 'members', report_name: 'AGM list' };

  it('accepts a filter the report actually reads', () => {
    const parsed = generateReportSchema.safeParse({
      ...base,
      filters: { status: [{ id: 'ACTIVE', name: 'Active' }] },
    });

    expect(parsed.success).toBe(true);
  });

  /* Accepting a filter the query ignores would report a narrowing that never
     happened — the caption would claim it, and the numbers would not show it. */
  it('rejects a filter that report does not read', () => {
    const parsed = generateReportSchema.safeParse({
      ...base,
      filters: { invoice_type: [{ id: 'EVENT', name: 'Event' }] },
    });

    expect(parsed.success).toBe(false);
  });

  it('requires a name', () => {
    expect(generateReportSchema.safeParse({ report_type: 'members' }).success).toBe(false);
  });

  it('defaults include_details to false', () => {
    const parsed = generateReportSchema.parse(base);

    expect(parsed.include_details).toBe(false);
  });
});

describe('summarise', () => {
  it('counts the members', () => {
    const figures = summarise('members', [
      { member_code: 'A', status: 'ACTIVE' },
      { member_code: 'B', status: 'DRAFT' },
    ]);

    expect(figures['Total Members']).toBe(2);
  });

  /* Money is summed as a string-safe integer count of paise would be overkill
     here, but the figures must still be numbers Excel can total. */
  it('totals the revenue columns', () => {
    const figures = summarise('revenue', [
      { period: '2026-08', invoices: 5, billed: '73800', collected: '50200', outstanding: '23600' },
    ]);

    expect(figures['Total Billed']).toBe(73800);
    expect(figures['Total Collected']).toBe(50200);
    expect(figures['Total Outstanding']).toBe(23600);
  });

  /* A lapsed term is the row the renewals report exists to surface. */
  it('counts lapsed and soon-due terms separately', () => {
    const figures = summarise('renewals', [
      { days_remaining: -12 },
      { days_remaining: 14 },
      { days_remaining: 900 },
    ]);

    expect(figures['Already Lapsed']).toBe(1);
    expect(figures['Due Within 30 Days']).toBe(1);
    expect(figures['Total Terms']).toBe(3);
  });

  it('totals bookings, attendees and revenue for events', () => {
    const figures = summarise('events', [
      { registrations: 3, attendees: 3, revenue: '3000' },
      { registrations: 3, attendees: 4, revenue: '6000' },
    ]);

    expect(figures['Total Bookings']).toBe(6);
    expect(figures['Total Attendees']).toBe(7);
    expect(figures['Total Revenue']).toBe(9000);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run src/modules/report/report.generate.test.ts`
Expected: FAIL — `generateReportSchema` and `summarise` are not exported.

- [ ] **Step 3: Add the generate schema**

In `report.types.ts`:

```ts
/**
 * A worksheet cannot hold more than this. A result beyond it is refused at
 * generate time rather than silently truncated — a file that looks complete but
 * has quietly dropped rows is worse than no file at all.
 */
export const EXCEL_MAX_ROWS = 1_048_576;

export const generateReportSchema = z
  .object({
    report_type: z.enum(REPORT_TYPES),
    report_name: z.string().trim().min(1).max(200),
    from_date: dateOnly,
    to_date: dateOnly,
    filters: z.record(z.string(), z.array(filterRefSchema).nonempty()).default({}),
    include_details: z.boolean().default(false),
  })
  .superRefine((value, ctx) => {
    const allowed = REPORT_FILTER_KEYS[value.report_type] as readonly string[];

    for (const key of Object.keys(value.filters)) {
      if (!allowed.includes(key)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['filters', key],
          // Accepting a filter the query ignores would record a narrowing that
          // never happened: the sheet's caption would claim it and the numbers
          // would not show it.
          message: `Filter "${key}" is not valid for a ${value.report_type} report.`,
        });
      }
    }
  });

export type GenerateReportInput = z.infer<typeof generateReportSchema>;

export const listGeneratedSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).default(20).transform((v) => Math.min(v, 100)),
  search: z.string().trim().min(1).max(200).optional(),
  report_type: z.enum(REPORT_TYPES).optional(),
  generated_by: z.string().regex(/^\d+$/).optional(),
});

export type ListGeneratedQuery = z.infer<typeof listGeneratedSchema>;

export const generatedIdParamSchema = z.object({
  id: z.string().regex(/^\d+$/, 'validation.invalidId'),
});
```

- [ ] **Step 4: Add `summarise` to the registry**

In `report.service.ts`, add a `summarise` field to the `Definition` interface and to each of the four entries:

```ts
interface Definition {
  label: string;
  columns: ReportColumn[];
  run: (db: typeof prisma, params: repo.ReportParams) => Promise<repo.ReportQueryResult>;
  /**
   * The headline figures for the Summary sheet.
   *
   * Computed here, from the same rows the report returned, so the totals can
   * never disagree with the rows they sit above — which is what a second query
   * for "the totals" eventually does.
   */
  summarise: (rows: ReportRow[]) => Record<string, string | number>;
}
```

`members`:
```ts
    summarise: (rows) => ({ 'Total Members': rows.length }),
```

`revenue`:
```ts
    summarise: (rows) => ({
      Months: rows.length,
      'Total Billed': sum(rows, 'billed'),
      'Total Collected': sum(rows, 'collected'),
      'Total Outstanding': sum(rows, 'outstanding'),
    }),
```

`renewals`:
```ts
    summarise: (rows) => ({
      'Total Terms': rows.length,
      // The two rows the report exists to surface, called out rather than left
      // to be counted by eye down a column of dates.
      'Already Lapsed': rows.filter((r) => Number(r.days_remaining) < 0).length,
      'Due Within 30 Days': rows.filter(
        (r) => Number(r.days_remaining) >= 0 && Number(r.days_remaining) <= 30,
      ).length,
    }),
```

`events`:
```ts
    summarise: (rows) => ({
      Events: rows.length,
      'Total Bookings': sum(rows, 'registrations'),
      'Total Attendees': sum(rows, 'attendees'),
      'Total Revenue': sum(rows, 'revenue'),
    }),
```

and the helper, above `REPORTS`:

```ts
/** Sum one column across the rows. Money arrives as a string; it totals as a number. */
const sum = (rows: ReportRow[], key: string): number =>
  rows.reduce((total, row) => total + Number(row[key] ?? 0), 0);

export const summarise = (
  type: ReportType,
  rows: ReportRow[],
): Record<string, string | number> => REPORTS[type].summarise(rows);
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && npx vitest run src/modules/report/report.generate.test.ts`
Expected: PASS (8 tests).

- [ ] **Step 6: Add the audit action**

In `backend/src/constant/audit.constant.ts`, inside `AUDIT_ACTIONS`:

```ts
  /** A report was generated. `after` carries its type, name and row count. */
  REPORT_GENERATED: 'report.generated',
```

- [ ] **Step 7: Add the repository writes**

In `report.repository.ts`:

```ts
export interface GeneratedReportRow {
  id: bigint;
  report_type: string;
  report_name: string;
  from_date: Date | null;
  to_date: Date | null;
  filters: unknown;
  include_details: boolean;
  report_data: unknown;
  status: string;
  row_count: bigint;
  generated_by: bigint;
  createdAt: Date;
}

export const insertGeneratedReport = async (
  db: Db,
  input: {
    reportType: string;
    reportName: string;
    fromDate: string | null;
    toDate: string | null;
    filters: unknown;
    includeDetails: boolean;
    reportData: unknown;
    rowCount: number;
    generatedBy: bigint;
  },
): Promise<GeneratedReportRow> =>
  db.generatedReport.create({
    data: {
      report_type: input.reportType,
      report_name: input.reportName,
      from_date: input.fromDate ? new Date(input.fromDate) : null,
      to_date: input.toDate ? new Date(input.toDate) : null,
      filters: input.filters as never,
      include_details: input.includeDetails,
      report_data: input.reportData as never,
      status: 'ready',
      row_count: BigInt(input.rowCount),
      generated_by: input.generatedBy,
    },
  }) as unknown as Promise<GeneratedReportRow>;
```

- [ ] **Step 8: Add `generateReport` to the service**

```ts
/**
 * Run a report once and keep the answer.
 *
 * The row is written INSIDE the transaction that writes its audit row, so a
 * report that appears in the list always has a trail saying who ran it.
 *
 * Detail rows are stored only when they were asked for. An unticked report
 * keeps its summary and its row count and nothing else — the count still says
 * how many rows matched, so a later "include detail" run is a decision made
 * with the size in hand.
 */
export const generateReport = async (
  input: GenerateReportInput,
  actor: { id: bigint; ip: string | null; userAgent: string | null; requestId: string | null },
): Promise<GeneratedReportDto> => {
  const definition = REPORTS[input.report_type];
  const params = toRepoParams(input.report_type, input.filters, input.from_date, input.to_date);

  const result = await definition.run(prisma, params);

  if (result.total > EXCEL_MAX_ROWS) {
    throw new AppError({
      errorType: ERROR_TYPES.INVALID_REQUEST,
      message: `This report matches ${result.total.toLocaleString('en-IN')} rows, more than a spreadsheet can hold. Narrow the filters and try again.`,
    });
  }

  const reportData = {
    summary: definition.summarise(result.rows),
    detail: input.include_details ? result.rows : null,
    row_count: result.total,
  };

  return prisma.$transaction(async (tx) => {
    const row = await repo.insertGeneratedReport(tx, {
      reportType: input.report_type,
      reportName: input.report_name,
      fromDate: input.from_date ?? null,
      toDate: input.to_date ?? null,
      filters: input.filters,
      includeDetails: input.include_details,
      reportData,
      rowCount: result.total,
      generatedBy: actor.id,
    });

    await writeAudit(tx, {
      action: AUDIT_ACTIONS.REPORT_GENERATED,
      entityName: 'GeneratedReports',
      entityId: row.id,
      after: {
        report_type: input.report_type,
        report_name: input.report_name,
        row_count: result.total,
      },
      actorType: ACTOR_TYPES.ADMIN,
      actorId: actor.id,
      ip: actor.ip,
      userAgent: actor.userAgent,
      requestId: actor.requestId,
    });

    return toGeneratedDto(row);
  });
};
```

Add the DTO mapper beside it:

```ts
export interface GeneratedReportDto {
  id: string;
  report_type: ReportType;
  report_name: string;
  from_date: string | null;
  to_date: string | null;
  filters: ReportFilters;
  include_details: boolean;
  status: string;
  row_count: number;
  generated_by: string;
  generated_by_name?: string | null;
  createdAt: string;
}

const toGeneratedDto = (row: repo.GeneratedReportRow & { generated_by_name?: string | null }): GeneratedReportDto => ({
  id: row.id.toString(),
  report_type: row.report_type as ReportType,
  report_name: row.report_name,
  from_date: row.from_date ? row.from_date.toISOString().slice(0, 10) : null,
  to_date: row.to_date ? row.to_date.toISOString().slice(0, 10) : null,
  filters: (row.filters ?? {}) as ReportFilters,
  include_details: row.include_details,
  status: row.status,
  row_count: Number(row.row_count),
  generated_by: row.generated_by.toString(),
  generated_by_name: row.generated_by_name ?? null,
  createdAt: row.createdAt.toISOString(),
});
```

- [ ] **Step 9: Run every report test**

Run: `cd backend && npx vitest run src/modules/report`
Expected: PASS.

- [ ] **Step 10: Lint, typecheck, stage**

Run: `cd backend && npm run lint && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"`
Expected: lint clean, still **54**.

```bash
git -C backend add src/modules/report src/constant/audit.constant.ts
# then ASK the user before running git commit
```

---

### Task 5: List, detail and the new endpoint set

**Files:**
- Modify: `backend/src/modules/report/report.repository.ts`
- Modify: `backend/src/modules/report/report.service.ts`
- Modify: `backend/src/modules/report/report.controller.ts`
- Modify: `backend/src/modules/report/report.routes.ts`

**Interfaces:**
- Consumes: `GeneratedReportDto`, `generateReportSchema`, `listGeneratedSchema`, `generatedIdParamSchema` (Task 4)
- Produces:
  - `POST /api/v1/admin/reports` → `report.create`
  - `GET /api/v1/admin/reports` → `report.view`
  - `GET /api/v1/admin/reports/:id` → `report.view`
  - `GET /api/v1/admin/reports/:id/export` → `report.export`
  - `listGeneratedReports(query)`, `getGeneratedReport(id)` in the service

- [ ] **Step 1: Add the list and detail reads**

In `report.repository.ts`:

```ts
/**
 * The list, newest first.
 *
 * The generator's name is joined in — unlike the audit log's actor, this IS a
 * foreign key (ON DELETE RESTRICT), so a report can never point at a staff row
 * that is gone and the join can never drop a row.
 */
export const listGeneratedReports = async (
  db: Db,
  params: { page: number; limit: number; search?: string; reportType?: string; generatedBy?: string },
): Promise<{ rows: (GeneratedReportRow & { generated_by_name: string })[]; total: number }> => {
  const offset = (params.page - 1) * params.limit;
  const search = params.search ? `%${params.search}%` : null;
  const reportType = params.reportType ?? null;
  const generatedBy = params.generatedBy ?? null;

  const rows = await db.$queryRaw<((GeneratedReportRow & { generated_by_name: string }) & { total: bigint })[]>(Prisma.sql`
    SELECT g."id", g."report_type", g."report_name", g."from_date", g."to_date",
           g."filters", g."include_details", g."status", g."row_count",
           g."generated_by", g."createdAt",
           au."full_name" AS generated_by_name,
           COUNT(*) OVER () AS total
      FROM "GeneratedReports" g
      JOIN "AdminUsers" au ON au."id" = g."generated_by"
     WHERE (${search}::text IS NULL OR g."report_name" ILIKE ${search}::text)
       AND (${reportType}::text IS NULL OR g."report_type" = ${reportType}::text)
       AND (${generatedBy}::bigint IS NULL OR g."generated_by" = ${generatedBy}::bigint)
     ORDER BY g."createdAt" DESC, g."id" DESC
     LIMIT ${params.limit} OFFSET ${offset}
  `);

  return {
    rows: rows.map(({ total: _total, ...row }) => ({ ...row, report_data: {} })),
    total: rows[0] ? Number(rows[0].total) : 0,
  };
};

/** One report, with its stored result. */
export const findGeneratedReport = async (
  db: Db,
  id: bigint,
): Promise<(GeneratedReportRow & { generated_by_name: string }) | null> => {
  const rows = await db.$queryRaw<(GeneratedReportRow & { generated_by_name: string })[]>(Prisma.sql`
    SELECT g.*, au."full_name" AS generated_by_name
      FROM "GeneratedReports" g
      JOIN "AdminUsers" au ON au."id" = g."generated_by"
     WHERE g."id" = ${id}
  `);

  return rows[0] ?? null;
};
```

- [ ] **Step 2: Add the service functions**

```ts
export const listGeneratedReports = async (
  query: ListGeneratedQuery,
): Promise<{ rows: GeneratedReportDto[]; total: number }> => {
  const result = await repo.listGeneratedReports(prisma, {
    page: query.page,
    limit: query.limit,
    ...(query.search ? { search: query.search } : {}),
    ...(query.report_type ? { reportType: query.report_type } : {}),
    ...(query.generated_by ? { generatedBy: query.generated_by } : {}),
  });

  return { rows: result.rows.map(toGeneratedDto), total: result.total };
};

/** One report, with the stored figures and — if they were kept — its rows. */
export const getGeneratedReport = async (
  id: bigint,
): Promise<GeneratedReportDto & { columns: ReportColumn[]; summary: Record<string, unknown>; detail: ReportRow[] | null }> => {
  const row = await repo.findGeneratedReport(prisma, id);

  if (!row) {
    throw new AppError({ errorType: ERROR_TYPES.NOT_FOUND, messageKey: 'report.notFound' });
  }

  const data = (row.report_data ?? {}) as {
    summary?: Record<string, unknown>;
    detail?: ReportRow[] | null;
  };

  return {
    ...toGeneratedDto(row),
    columns: REPORTS[row.report_type as ReportType].columns,
    summary: data.summary ?? {},
    detail: data.detail ?? null,
  };
};
```

- [ ] **Step 3: Replace the controller**

`report.controller.ts` — replace `runReport` with:

```ts
const actor = (req: Request) => {
  if (req.actor?.id === undefined) {
    throw new AppError({ errorType: ERROR_TYPES.UNAUTHORIZED, messageKey: 'auth.unauthorized' });
  }

  return {
    id: req.actor.id,
    ip: req.ip ?? null,
    userAgent: req.get('user-agent') ?? null,
    requestId: req.requestId ?? null,
  };
};

/** `POST /admin/reports` — run one now and keep the answer. */
export const generateReport = handler(async (req, res) => {
  const result = await service.generateReport(req.body as never, actor(req));

  handleApiResponse(res, {
    responseType: RES_STATUS.CREATE,
    messageKey: 'report.generated',
    data: result,
  });
});

/** `GET /admin/reports` — the reports anyone has generated, newest first. */
export const listReports = handler(async (req, res) => {
  const query = req.query as unknown as Parameters<typeof service.listGeneratedReports>[0];
  const result = await service.listGeneratedReports(query);

  handleApiResponse(res, {
    responseType: RES_STATUS.GET,
    data: result.rows,
    pagination: { page: query.page, limit: query.limit, total: result.total },
  });
});

/** `GET /admin/reports/:id` — one report's stored figures. */
export const getReport = handler(async (req, res) => {
  const result = await service.getGeneratedReport(BigInt(req.params.id));

  handleApiResponse(res, { responseType: RES_STATUS.GET, data: result });
});
```

- [ ] **Step 4: Replace the routes**

`report.routes.ts` — replace both route registrations:

```ts
const REPORTS = '/reports';

/**
 * Three permissions, not one. `report.view` reads the list; `report.create`
 * runs a new one; `report.export` takes the data out of the building. They are
 * separate because they are different risks, and the split exists the day a
 * clerk should read reports without running heavy queries or forwarding files.
 */
reportRouter.post(
  REPORTS,
  authenticateAdmin,
  authorize('report.create'),
  validateRequest({ body: generateReportSchema }),
  controller.generateReport,
);

reportRouter.get(
  REPORTS,
  authenticateAdmin,
  authorize('report.view'),
  validateRequest({ query: listGeneratedSchema }),
  controller.listReports,
);

/**
 * Declared before `/:id` — Express matches in order, and the parameterised
 * route would otherwise swallow this one.
 */
reportRouter.get(
  `${REPORTS}/:id/export`,
  authenticateAdmin,
  authorize('report.export'),
  validateRequest({ params: generatedIdParamSchema }),
  controller.exportReport,
);

reportRouter.get(
  `${REPORTS}/:id`,
  authenticateAdmin,
  authorize('report.view'),
  validateRequest({ params: generatedIdParamSchema }),
  controller.getReport,
);
```

- [ ] **Step 5: Add the two message keys**

In `backend/src/locales/en.json` (and every other locale file present), add under the existing keys:

```json
  "report.generated": "Report generated.",
  "report.notFound": "That report does not exist."
```

- [ ] **Step 6: Verify the routes answer**

Run:
```bash
cd backend && for p in "reports" "reports/1" "reports/1/export"; do
  printf "%-20s -> " "$p"; curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 "http://localhost:4000/api/v1/admin/$p"; done
```
Expected: `401` on all three — registered and guarded.

- [ ] **Step 7: Lint, typecheck, run the suite, stage**

Run: `cd backend && npm run lint && npx vitest run && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"`
Expected: lint clean, all tests pass, still **54**.

```bash
git -C backend add src/modules/report src/locales
# then ASK the user before running git commit
```

---

### Task 6: The Excel — Summary sheet and Detail sheet

**Files:**
- Modify: `backend/src/modules/report/report.service.ts`
- Modify: `backend/src/modules/report/report.controller.ts`
- Create: `backend/src/modules/report/report.export.test.ts`

**Interfaces:**
- Consumes: `getGeneratedReport` (Task 5), `toWorkbook` from `@helpers/excel`
- Produces:
  - `buildReportFilename(report: GeneratedReportDto): string`
  - `buildReportFile(id: bigint): Promise<{ filename: string; buffer: Buffer }>`

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/report/report.export.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { buildReportFilename } from '@modules/report/report.service';

const base = {
  id: '1',
  report_type: 'members' as const,
  report_name: 'AGM list',
  from_date: null,
  to_date: null,
  include_details: false,
  status: 'ready',
  row_count: 238,
  generated_by: '4',
  createdAt: '2026-09-02T09:14:00.000Z',
};

describe('buildReportFilename', () => {
  /* A downloads folder holding six files called members-2026-09-02.xlsx is
     useless. The filters are the only thing that tells them apart. */
  it('puts the filter names in the filename', () => {
    const name = buildReportFilename({
      ...base,
      filters: {
        status: [{ id: 'ACTIVE', name: 'Active' }],
        category_id: [{ id: '3', name: 'Gold' }],
      },
    });

    expect(name).toBe('members-active-gold-2026-09-02.xlsx');
  });

  it('falls back to the type and date when nothing was filtered', () => {
    expect(buildReportFilename({ ...base, filters: {} })).toBe('members-2026-09-02.xlsx');
  });

  /* A filename long enough to be rejected by a filesystem is a download that
     silently fails, so it is trimmed rather than left to chance. */
  it('trims a very long name without leaving a trailing dash', () => {
    const name = buildReportFilename({
      ...base,
      filters: {
        city: Array.from({ length: 40 }, (_, i) => ({ id: String(i), name: `Very Long City ${i}` })),
      },
    });

    expect(name.length).toBeLessThanOrEqual(120);
    expect(name).toMatch(/[a-z0-9]-\d{4}-\d{2}-\d{2}\.xlsx$/);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && npx vitest run src/modules/report/report.export.test.ts`
Expected: FAIL — `buildReportFilename` is not exported.

- [ ] **Step 3: Implement the filename**

In `report.service.ts`:

```ts
const MAX_FILENAME_LENGTH = 120;

const slug = (value: string): string =>
  value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

/**
 * `{report-type}-{filters}-{date}.xlsx`.
 *
 * The filter labels are in the name because a downloads folder holding six
 * files called `members-2026-09-02.xlsx` is useless. The whole reason filters
 * are recorded is so a report can be told apart from its siblings, and the
 * filename is the first place that has to hold.
 */
export const buildReportFilename = (report: {
  report_type: string;
  filters: ReportFilters;
  createdAt: string;
}): string => {
  const date = report.createdAt.slice(0, 10);
  const labels = Object.values(report.filters ?? {})
    .flatMap((refs) => refs.map((ref) => slug(ref.name)))
    .filter(Boolean);

  const stem = [slug(report.report_type), ...labels].join('-');
  const suffix = `-${date}.xlsx`;
  const room = MAX_FILENAME_LENGTH - suffix.length;

  return `${stem.length > room ? stem.slice(0, room).replace(/-+$/, '') : stem}${suffix}`;
};
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd backend && npx vitest run src/modules/report/report.export.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Build the two-sheet workbook**

Replace `runReportForExport` and `exportCaption` in `report.service.ts` with:

```ts
/**
 * The saved report as a workbook: a Summary sheet always, a Detail sheet when
 * the rows were kept.
 *
 * Rebuilt from the stored snapshot on every download rather than from a fresh
 * query — that is what makes the file the answer the report gave when it was
 * run, which is the entire reason reports are saved rather than recomputed.
 */
export const buildReportFile = async (
  id: bigint,
): Promise<{ filename: string; buffer: Buffer }> => {
  const report = await getGeneratedReport(id);
  const wb = new ExcelJS.Workbook();

  const summary = wb.addWorksheet('Summary');
  summary.getColumn(1).width = 26;
  summary.getColumn(2).width = 48;

  const title = summary.addRow([`ILGDA — ${report.report_name}`]);

  // Painted cell by cell across exactly two columns. A fill assigned to the ROW
  // is written as a row-level style, and Excel renders that across all 16,384
  // columns — a two-column sheet then shows a page-wide band.
  for (let column = 1; column <= 2; column += 1) {
    const cell = title.getCell(column);
    cell.font = { bold: true, size: 14, color: { argb: 'FFFFFFFF' } };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1F2937' } };
  }

  summary.addRow([
    `Generated: ${new Date(report.createdAt).toLocaleString('en-IN')}${report.generated_by_name ? ` · By: ${report.generated_by_name}` : ''}`,
  ]);
  summary.addRow([]);
  summary.addRow(['Report Type', reportLabel(report.report_type)]);
  summary.addRow([
    'Date Range',
    report.from_date && report.to_date ? `${report.from_date} to ${report.to_date}` : 'N/A',
  ]);

  // Filters are stated before any figure. A filtered number read as an
  // association-wide total is the failure this whole design exists to prevent.
  const entries = Object.entries(report.filters ?? {});

  if (entries.length === 0) {
    summary.addRow(['Filters Applied', 'None (all records)']);
  } else {
    entries.forEach(([key, refs], index) => {
      const label = key
        .replace(/_ids?$/, '')
        .replace(/_/g, ' ')
        .replace(/\b\w/g, (c) => c.toUpperCase());

      summary.addRow([
        index === 0 ? 'Filters Applied' : '',
        `${label}: ${refs.map((ref) => ref.name).join(', ')}`,
      ]);
    });
  }

  summary.addRow([]);

  for (const [label, figure] of Object.entries(report.summary)) {
    summary.addRow([label, typeof figure === 'number' ? figure : String(figure)]);
  }

  if (report.detail && report.detail.length > 0) {
    const buffer = await toWorkbook(
      report.detail,
      report.columns.map((column) => ({
        header: column.header,
        // Money and counts land as real numbers so the office can total the
        // column; everything else stays text.
        value: (row: ReportRow) => {
          const value = row[column.key];

          if (value === null || value === undefined) return '';
          if (column.type === 'money' || column.type === 'number') return Number(value);

          return value as string;
        },
        ...(column.width !== undefined ? { width: column.width } : {}),
      })),
      { sheetName: 'Detail' },
    );

    const detailWb = new ExcelJS.Workbook();
    await detailWb.xlsx.load(buffer);

    const source = detailWb.worksheets[0];

    if (source) {
      const target = wb.addWorksheet('Detail');
      target.columns = source.columns;
      source.eachRow((row, index) => {
        const copied = target.getRow(index);
        copied.values = row.values;
        copied.font = row.font;
        copied.fill = row.fill;
        copied.commit();
      });
      target.views = [{ state: 'frozen', ySplit: 1 }];
    }
  }

  return {
    filename: buildReportFilename(report),
    buffer: Buffer.from(await wb.xlsx.writeBuffer()),
  };
};
```

- [ ] **Step 6: Point the controller at it**

Replace `exportReport` in `report.controller.ts`:

```ts
/** `GET /admin/reports/:id/export` — the saved report as an .xlsx. */
export const exportReport = handler(async (req, res) => {
  const { filename, buffer } = await service.buildReportFile(BigInt(req.params.id));

  res.setHeader('Content-Type', XLSX_MIME);
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.status(200).send(buffer);
});
```

- [ ] **Step 7: Verify the sheets against a real generated report**

Run:
```bash
cd backend && cat > src/__x.ts <<'EOF'
import ExcelJS from 'exceljs';
import { generateReport, buildReportFile } from '@modules/report/report.service';
const main = async () => {
  const made = await generateReport(
    { report_type: 'members', report_name: 'Probe', filters: { status: [{ id: 'ACTIVE', name: 'Active' }] }, include_details: true } as never,
    { id: 1n, ip: null, userAgent: null, requestId: null },
  );
  const { filename, buffer } = await buildReportFile(BigInt(made.id));
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buffer);
  console.log('filename:', filename);
  console.log('sheets  :', wb.worksheets.map((s) => s.name));
  const s = wb.worksheets[0]!;
  for (let r = 1; r <= 10; r += 1) console.log(r, s.getRow(r).getCell(1).value, '|', s.getRow(r).getCell(2).value);
  console.log('detail rows:', (wb.getWorksheet('Detail')?.rowCount ?? 1) - 1, 'vs row_count', made.row_count);
};
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
EOF
npx tsx src/__x.ts; rm -f src/__x.ts
```
Expected: sheets `['Summary', 'Detail']`; `Filters Applied` appears **before** `Total Members`; the Detail row count equals `row_count`.

- [ ] **Step 8: Lint, typecheck, suite, stage**

Run: `cd backend && npm run lint && npx vitest run && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"`
Expected: lint clean, tests pass, still **54**.

```bash
git -C backend add src/modules/report
# then ASK the user before running git commit
```

---

### Task 7: Prune reports older than a year

**Files:**
- Modify: `backend/src/jobs/definitions.ts`

**Interfaces:**
- Consumes: the `GeneratedReport` model (Task 1)
- Produces: `reportPruneJob: JobDefinition` registered in `jobDefinitions`

- [ ] **Step 1: Add the job**

In `definitions.ts`, beside the other jobs:

```ts
/** A report is worth keeping for one annual cycle: at the 2027 AGM you want the
 *  2026 equivalent to compare against, and nothing older. */
const GENERATED_REPORT_RETENTION_DAYS = 365;

/**
 * Delete generated reports past their retention.
 *
 * The row is small; what grows is `report_data`, which holds every detail row of
 * every report anyone ticked the box for. Left alone that is the one table here
 * that grows without bound, and it grows fastest exactly when the feature is
 * being used well.
 */
export const reportPruneJob: JobDefinition = {
  name: 'report.prune',
  schedule: '30 3 * * *',
  description: 'Deletes generated reports older than a year.',
  handler: async () => {
    const result = await prisma.generatedReport.deleteMany({
      where: { createdAt: { lt: daysAgo(GENERATED_REPORT_RETENTION_DAYS) } },
    });

    return result.count;
  },
};
```

- [ ] **Step 2: Register it**

Add `reportPruneJob` to the exported `jobDefinitions` array in the same file.

- [ ] **Step 3: Verify it runs and reports a count**

Run:
```bash
cd backend && npx tsx -e "
import { reportPruneJob } from './src/jobs/definitions';
reportPruneJob.handler().then((n) => { console.log('pruned', n); process.exit(0); });
"
```
Expected: `pruned 0` — nothing is a year old yet, and it must not throw.

- [ ] **Step 4: Lint, typecheck, stage**

Run: `cd backend && npm run lint && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"`
Expected: lint clean, still **54**.

```bash
git -C backend add src/jobs
# then ASK the user before running git commit
```

---

### Task 8: Admin service and types

**Files:**
- Modify: `admin/src/constant/endpoints.ts`
- Modify: `admin/src/services/reportsService.ts`

**Interfaces:**
- Consumes: the four endpoints from Task 5
- Produces:
  - `interface FilterRef { id: string; name: string }`
  - `interface GeneratedReport` (list row) and `GeneratedReportDetail`
  - `ReportsService.generate(body)`, `.list(params)`, `.get(id)`, `.download(id)`

- [ ] **Step 1: Replace the endpoint entry**

In `endpoints.ts`, replace the `REPORTS` block:

```ts
  /**
   * Reports (M10, screen A-29). `report.view` reads the list, `report.create`
   * runs a new one, `report.export` downloads it.
   */
  REPORTS: {
    LIST: `${API_BASE}/admin/reports`,
    detail: (id: string) => `${API_BASE}/admin/reports/${id}`,
    export: (id: string) => `${API_BASE}/admin/reports/${id}/export`,
  },
```

- [ ] **Step 2: Rewrite the service**

Replace `admin/src/services/reportsService.ts` entirely:

```ts
import { ENDPOINTS } from '@/constant/endpoints';
import { BaseService, downloadFile, type ApiResult } from '@/services/BaseService';

/**
 * Reports (M10, screen A-29).
 *
 * A report is generated once and saved. The list is of past reports, not of
 * data — which is why there is no "run this report" call that returns rows.
 */

export const REPORT_TYPES = ['members', 'revenue', 'renewals', 'events'] as const;

export type ReportType = (typeof REPORT_TYPES)[number];

export type ColumnType = 'text' | 'number' | 'money' | 'date' | 'status';

export interface ReportColumn {
  key: string;
  header: string;
  type: ColumnType;
  domain?: string;
}

export type ReportRow = Record<string, string | number | null>;

/**
 * One filter selection. The NAME travels with the id deliberately: a report is
 * a historical record, and an id-only filter becomes unreadable the moment a
 * category or a company is renamed.
 */
export interface FilterRef {
  id: string;
  name: string;
}

export type ReportFilters = Record<string, FilterRef[]>;

export interface GeneratedReport {
  id: string;
  report_type: ReportType;
  report_name: string;
  from_date: string | null;
  to_date: string | null;
  filters: ReportFilters;
  include_details: boolean;
  status: 'queued' | 'running' | 'ready' | 'failed';
  row_count: number;
  generated_by: string;
  generated_by_name: string | null;
  createdAt: string;
}

export interface GeneratedReportDetail extends GeneratedReport {
  columns: ReportColumn[];
  summary: Record<string, string | number>;
  /** NULL when the report was generated without the detail box ticked. */
  detail: ReportRow[] | null;
}

export interface GenerateReportBody {
  report_type: ReportType;
  report_name: string;
  from_date?: string;
  to_date?: string;
  filters?: ReportFilters;
  include_details?: boolean;
}

export interface ListReportsParams {
  page?: number;
  limit?: number;
  search?: string;
  report_type?: ReportType;
  generated_by?: string;
}

const query = (params: ListReportsParams = {}): string => {
  const search = new URLSearchParams();

  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== '') search.set(key, String(value));
  });

  const qs = search.toString();

  return qs ? `?${qs}` : '';
};

export const ReportsService = {
  generate: (body: GenerateReportBody): Promise<ApiResult<GeneratedReport>> =>
    BaseService.post(ENDPOINTS.REPORTS.LIST, body),

  list: (params?: ListReportsParams): Promise<ApiResult<GeneratedReport[]>> =>
    BaseService.get(`${ENDPOINTS.REPORTS.LIST}${query(params)}`),

  get: (id: string): Promise<ApiResult<GeneratedReportDetail>> =>
    BaseService.get(ENDPOINTS.REPORTS.detail(id)),

  /** The filename comes back on `Content-Disposition` — the server knows the filters. */
  download: (id: string): Promise<void> =>
    downloadFile(ENDPOINTS.REPORTS.export(id), `report-${id}.xlsx`),
};

export default ReportsService;
```

- [ ] **Step 3: Typecheck**

Run: `cd admin && npm run typecheck`
Expected: FAIL — `Reports.tsx` still uses the old `run`/`export` methods. That is Task 10.

- [ ] **Step 4: Stage**

```bash
git -C admin add src/constant/endpoints.ts src/services/reportsService.ts
# then ASK the user before running git commit
```

---

### Task 9: The generate drawer

**Files:**
- Create: `admin/src/pages/reports/reportSpecs.ts`
- Create: `admin/src/pages/reports/GenerateReportDrawer.tsx`

**Interfaces:**
- Consumes: `ReportsService.generate`, `FilterRef`, `ReportType` (Task 8)
- Produces:
  - `REPORT_SPECS: ReportSpec[]` with `{ key, title, description, filterFields, dateLabel? }`
  - `<GenerateReportDrawer open onClose onGenerated prefill />`

- [ ] **Step 1: Write the report specs**

Create `admin/src/pages/reports/reportSpecs.ts`:

```ts
import type { ReportType } from '@/services/reportsService';

/** Where a filter's options come from. */
export type FilterSource = 'memberStatus' | 'termStatus' | 'invoiceType' | 'category' | 'member' | 'event';

export interface FilterField {
  /** The key the API stores this under. Must match `REPORT_FILTER_KEYS`. */
  key: string;
  label: string;
  source: FilterSource;
}

export interface ReportSpec {
  key: ReportType;
  title: string;
  /** What the report answers, in the office's language. */
  description: string;
  filterFields: FilterField[];
  /** What a date range means here — it is a different date on every report. */
  dateLabel?: string;
}

export const REPORT_SPECS: ReportSpec[] = [
  {
    key: 'members',
    title: 'Members',
    description: 'Who our members are, by category, status and location.',
    filterFields: [
      { key: 'status', label: 'Membership Status', source: 'memberStatus' },
      { key: 'category_id', label: 'Category', source: 'category' },
      { key: 'member_id', label: 'Member', source: 'member' },
    ],
  },
  {
    key: 'revenue',
    title: 'Revenue',
    description: 'What we billed and collected, by month. Drafts and cancelled invoices excluded.',
    filterFields: [
      { key: 'invoice_type', label: 'Invoice Type', source: 'invoiceType' },
      { key: 'member_id', label: 'Member', source: 'member' },
    ],
    dateLabel: 'Invoice issued',
  },
  {
    key: 'renewals',
    title: 'Renewals Due',
    description: 'Memberships by expiry date, soonest first. A negative days-left has lapsed.',
    filterFields: [
      { key: 'status', label: 'Cover Status', source: 'termStatus' },
      { key: 'member_id', label: 'Member', source: 'member' },
    ],
    dateLabel: 'Expires between',
  },
  {
    key: 'events',
    title: 'Event Attendance',
    description: 'Bookings, attendees and revenue per event. Confirmed bookings only.',
    filterFields: [{ key: 'event_id', label: 'Event', source: 'event' }],
    dateLabel: 'Event date',
  },
];

/** Fixed option lists — enums, so they need no request. */
export const STATIC_OPTIONS: Record<string, { id: string; name: string }[]> = {
  memberStatus: [
    { id: 'DRAFT', name: 'Draft' },
    { id: 'PENDING', name: 'Awaiting payment' },
    { id: 'ACTIVE', name: 'Active' },
    { id: 'SUSPENDED', name: 'Suspended' },
    { id: 'EXPIRED', name: 'Expired' },
    { id: 'TERMINATED', name: 'Terminated' },
  ],
  termStatus: [
    { id: 'PENDING_PAYMENT', name: 'Awaiting payment' },
    { id: 'ACTIVE', name: 'Covered' },
    { id: 'EXPIRED', name: 'Lapsed' },
    { id: 'CANCELLED', name: 'Cancelled' },
  ],
  invoiceType: [
    { id: 'MEMBERSHIP', name: 'New membership' },
    { id: 'RENEWAL', name: 'Renewal' },
    { id: 'EVENT', name: 'Event' },
    { id: 'OTHER', name: 'Other' },
  ],
};
```

- [ ] **Step 2: Build the drawer**

Create `admin/src/pages/reports/GenerateReportDrawer.tsx`. Requirements, each of which is a review gate:

1. **The first field is the report, and nothing below it renders until one is picked.** The drawer opens as one question rather than a wall of inputs whose relevance the reader has to work out.
2. **The name auto-suggests and keeps re-suggesting** as the filters change — `{title} — {filter summary}`, where a filter holding one value shows its name and several show `N selected`. The effect depends on the derived suggestion, never on what the user typed, so it cannot overwrite an edit in progress.
3. Filters render from `spec.filterFields`. `memberStatus` / `termStatus` / `invoiceType` come from `STATIC_OPTIONS`; `category` from `MastersService.listCategories({ limit: 100 })`; **`member` and `event` search server-side** through `MembersService` and `EventService` — never a capped list, because a capped list silently cannot offer member 3,000.
4. Every selection is stored as `{ id, name }`.
5. The detail checkbox reads: *"Adds every matching row to the report and its download."* **It must not promise a notification** — background generation is not built.
6. Built from `@/components/ui`: `FormDrawer`, `FormSelect`, `MultiSelect`, `antd` `Form` / `Form.Item` / `Input` / `Switch` / `DatePicker`.

- [ ] **Step 3: Typecheck and lint**

Run: `cd admin && npm run typecheck && npm run lint`
Expected: both clean.

- [ ] **Step 4: Stage**

```bash
git -C admin add src/pages/reports
# then ASK the user before running git commit
```

---

### Task 10: The reports list screen

**Files:**
- Modify: `admin/src/pages/reports/Reports.tsx`
- Create: `admin/src/pages/reports/ReportSummaryDrawer.tsx`

**Interfaces:**
- Consumes: `ReportsService` (Task 8), `REPORT_SPECS`, `GenerateReportDrawer` (Task 9)
- Produces: the screen at `/reports`

- [ ] **Step 1: Replace the page**

`Reports.tsx` becomes the list. Requirements:

1. **`PageHeader title="Reports"`** with, in `actions`: `SearchInput` → `FilterDropdown` (Type, Generated By) → `Button variant="primary"` **Generate Report**, hidden without `report.create`.
2. **A card grid above the table** — one card per `REPORT_SPEC`, each opening the drawer with that report preselected.
3. **`DataTable`** with: Sr · Report Name · Type (`Badge`) · Status · Filters · Details · Generated By · Generated At · Actions.
4. **The Status cell shows the row count, not a chip:**
   - `ready` and `row_count > 0` → `238 rows`
   - `ready` and `row_count === 0` → `Ready`
   - `failed` → `StatusChip` danger, `Failed`
   - `queued` / `running` → `Generating…`
   The count is what anyone actually wants to know from that column.
5. **Filters cell** — an icon plus the count, with the filter names in a `Tooltip`. Not chips: chips stack a second line under every report name and push the other columns off the row.
6. **Details cell** — the word `Included`, or `NotAvailable`. Written out rather than ticked: a bare check has to be decoded, and this decides whether the download carries rows at all.
7. **`RowActions` with three actions:**
   - **View summary** — `Eye`, opens `ReportSummaryDrawer`, disabled unless `ready`
   - **Download Excel** — `Download`, disabled unless `ready`
   - **Run again** — `RotateCw`, opens the generate drawer prefilled from that row, hidden without `report.create`
8. **The toast after generating names the row count** — `Generated · 238 rows`. It is the one moment the person can check the result against what they asked for.

- [ ] **Step 2: Build the summary drawer**

`ReportSummaryDrawer.tsx` — fetches `ReportsService.get(id)` and shows: the report name, type, date range, who ran it, when; then **Filters Applied**; then the headline figures from `summary`. If `detail` is present, the first 20 rows below it with a line saying how many there are in total and that the download carries them all.

Filters appear **before** the figures here too, for the same reason they do in the sheet.

- [ ] **Step 3: Typecheck and lint**

Run: `cd admin && npm run typecheck && npm run lint`
Expected: both clean.

- [ ] **Step 4: Verify in the running app**

The dev servers are already up on `:3001` and `:4000` — **do not restart them.**
Open `http://localhost:3001/reports` and confirm, in order:

1. Four cards render.
2. Clicking **Members** opens the drawer with Members preselected and no filter fields visible until it is chosen.
3. Picking Status = Active rewrites the name to `Members — Active`.
4. **Generate** adds a row reading `2 rows` (your database has 2 active members).
5. **Download** produces `members-active-<date>.xlsx` with a Summary sheet whose `Filters Applied` line precedes `Total Members`.
6. **Run again** reopens the drawer with Status = Active already selected.

- [ ] **Step 5: Stage**

```bash
git -C admin add src/pages/reports
# then ASK the user before running git commit
```

---

### Task 11: Self-test pass

**Files:**
- None modified. This task is verification only.

**Interfaces:**
- Consumes: everything above

- [ ] **Step 1: Full backend suite**

Run: `cd backend && npx vitest run`
Expected: every file passes. Before this work the suite was **47 files / 331 tests**; it should now be larger and still fully green.

- [ ] **Step 2: Backend typecheck against the baseline**

Run: `cd backend && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -c "error TS"`
Expected: **54**. Any higher number is a regression introduced by this work.

- [ ] **Step 3: Admin typecheck and lint**

Run: `cd admin && npm run typecheck && npm run lint`
Expected: both clean.

- [ ] **Step 4: The gates from the module's definition of done**

Run:
```bash
cd backend && cat > src/__gate.ts <<'EOF'
import ExcelJS from 'exceljs';
import { generateReport, buildReportFile } from '@modules/report/report.service';
import { REPORT_TYPES } from '@modules/report/report.types';

const main = async () => {
  for (const type of REPORT_TYPES) {
    const made = await generateReport(
      { report_type: type, report_name: `Gate ${type}`, filters: {}, include_details: true } as never,
      { id: 1n, ip: null, userAgent: null, requestId: null },
    );
    const { buffer } = await buildReportFile(BigInt(made.id));
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(buffer);
    const detail = wb.getWorksheet('Detail');
    const sheetRows = detail ? detail.rowCount - 1 : 0;
    console.log(
      `${type.padEnd(9)} stored=${made.row_count} sheet=${sheetRows} ` +
        (made.row_count === sheetRows ? 'ROWS MATCH' : '*** MISMATCH ***'),
    );
  }
};
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
EOF
npx tsx src/__gate.ts; rm -f src/__gate.ts
```
Expected: **ROWS MATCH** on all four. The sheet's row count must equal the count the report recorded.

- [ ] **Step 5: Verify the audit trail**

Run:
```bash
cd backend && npx tsx -e "
import { prisma } from './src/db/prisma';
prisma.\$queryRawUnsafe('SELECT action, entity_name, after_json FROM \"AuditLogs\" WHERE action = \'report.generated\' ORDER BY id DESC LIMIT 3')
  .then((r) => { console.log(r); process.exit(0); });
"
```
Expected: rows naming the report type, name and row count of the reports just generated.

- [ ] **Step 6: Update the module docs**

Modify `docs/implementation-status.md` and `docs/modules/M10-dashboard-reports-org-audit.md`: reports are delivered as saved reports; note that background generation and the Member Statement report are deferred.

- [ ] **Step 7: Stage everything and ask**

```bash
git -C backend add -A && git -C admin add -A && git add docs
# then ASK the user before running git commit
```

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| §3 four reports, new member/event filters | 3 |
| §4 flow — cards, drawer, list, actions | 9, 10 |
| §5 no background generation | not built, by decision; the over-a-million refusal is Task 4 |
| §5 shared list + Generated By filter | 5, 10 |
| §5 one-year retention | 7 |
| §5 `report.create` | 2, 5 |
| §5 member filter on three reports, event on the fourth | 3 |
| §5 Member Statement deferred | not built, by decision |
| §6 data model | 1 |
| §7 Summary + Detail sheets, filters before figures | 6 |
| §7 real numbers in detail | 6 |
| §7 no row-level fill | 6 |
| §8 no polling needed while inline | n/a |

**Placeholder scan** — none. Every code step carries the code; the two UI tasks carry numbered requirements rather than source, which is the right altitude for a screen assembled from a documented component catalogue.

**Type consistency** — `FilterRef`, `ReportFilters`, `ReportColumn`, `ReportRow`, `ReportType` are named identically in `report.types.ts` and `reportsService.ts`. `toRepoParams` produces the `ReportParams` that Task 3 extends. `summarise` is defined in Task 4 and consumed in Task 6. `buildReportFilename` and `buildReportFile` are defined in Task 6 and consumed by the controller in the same task.

**One thing an executor must not get wrong:** the four report queries in `report.repository.ts` already exist and are verified against real data. Tasks 3 and 4 extend them. Do not rewrite them.
