# Member Directory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A searchable member directory, reachable only by a signed-in user whose own company is `ACTIVE`, with no public surface of any kind.

**Architecture:** One new backend module `modules/directory` with a **single** member-authenticated router — there is no public router, which is the whole point of the design. A viewer gate resolves the caller's company status from the database on every request and returns `403` with a reason code to anyone not `ACTIVE`. A presenter applies one explicit field allowlist. The customer app gets two pages under `(member)/directory` plus a lock screen; the admin app gets one read-only column and one settings switch. No new tables — every field already exists on `Members`, `MemberContacts`, `MemberAddresses` and `MemberCategories`.

**Tech Stack:** Express + Prisma + PostgreSQL, vitest (backend); Next.js 14 App Router + TypeScript (customer); React + TypeScript + the `association-admin-ui` catalogue (admin).

**Spec:** [`docs/specs/2026-08-31-member-directory.md`](../../specs/2026-08-31-member-directory.md)
**Plain-language version:** [`docs/directory-module-summary.md`](../../directory-module-summary.md)

---

## Global Constraints

- **Never build a public directory route.** No `/public/directory` router, no anonymous listing, no anonymous profile, no anonymous logo, no sitemap entry. This is decision D1 in `docs/client-decisions.md`.
- **The gate is `Members.status === 'ACTIVE'`, never "has a token".** A `DRAFT`, `PENDING`, `SUSPENDED`, `EXPIRED` or `TERMINATED` company gets `403`.
- **Read the status from the database on every request.** Never from a token claim. A member suspended five minutes ago must fail their next request.
- **A `403` carries a reason code and nothing else** — no partial list, no company count, no company name.
- **The field list is an explicit allowlist**, never "the row minus a few fields". Follow `modules/news/news.presenter.ts`.
- **Never return** `gst_number`, `pan_number`, `iec_code`, `trade_license_no`, any `MemberDocument`, `pincode`, or street address lines. Not to members, not to anyone but admin.
- **Never return `legal_name`.** It is searched; it is not displayed.
- **Never return `logo_path`.** Serve logos through the gated media endpoint by member id.
- **Joining date is a year**, not a date: `joined_on.getFullYear()`.
- Page size is **24**, enforced server-side as a hard cap.
- Base listing filter is fixed: `deletedAt: null, status: 'ACTIVE', directory_visible: true`, plus the `directory.enabled` setting.
- Admin screens use the `association-admin-ui` catalogue. No direct Ant Design imports.
- Migrations are additive. Never edit an applied migration.

---

## File Structure

**Backend — create**

| File | Responsibility |
|---|---|
| `src/modules/directory/directory.constants.ts` | Field allowlist, page size, reason codes, setting key |
| `src/modules/directory/directory.types.ts` | Zod query schemas and response interfaces |
| `src/modules/directory/directory.gate.ts` | The viewer gate — resolve caller's company, allow or throw |
| `src/modules/directory/directory.repository.ts` | Prisma reads: list, one, facets |
| `src/modules/directory/directory.presenter.ts` | Row → response, allowlist applied |
| `src/modules/directory/directory.service.ts` | Orchestration: gate, setting, repo, presenter |
| `src/modules/directory/directory.controller.ts` | Thin Express handlers |
| `src/modules/directory/directory.routes.ts` | One member router |
| `src/modules/directory/directory.gate.test.ts` | Gate behaviour per status |
| `src/modules/directory/directory.leak.test.ts` | The tests that keep the decision |
| `src/modules/directory/directory.search.test.ts` | Search, filters, pagination cap |
| `prisma/migrations/<ts>_directory_search_indexes/migration.sql` | GIN + city index |

**Backend — modify**

| File | Change |
|---|---|
| `src/constant/endPoints.constant.ts` | `DIRECTORY` already exists — no change needed, verify only |
| `src/helpers/settings.ts` | Add `DIRECTORY_ENABLED` to `SETTING_KEYS` |
| `src/routes/index.ts` | Mount `directoryRouter` under `/directory` |

**Customer — create**

| File | Responsibility |
|---|---|
| `src/app/(member)/directory/page.tsx` | List page |
| `src/app/(member)/directory/[slug]/page.tsx` | Profile page |
| `src/components/directory/DirectoryLock.tsx` | The 403 lock screen |
| `src/components/directory/DirectoryCard.tsx` | One result card |
| `src/services/DirectoryService.ts` | API client |

**Customer — modify / delete**

| File | Change |
|---|---|
| `src/app/(public)/directory/page.tsx` | **Delete.** The route must not exist publicly |
| `src/app/(member)/profile/…` | Add the listing tick-box and `about` field |

**Admin — modify**

| File | Change |
|---|---|
| `src/pages/members/…` | Add the *In directory* column |
| `src/pages/settings/…` | Add the `directory.enabled` switch |

---

## Task 1: The viewer gate

The single most important unit in the module. It decides who may see anything at all.

**Files:**
- Create: `backend/src/modules/directory/directory.constants.ts`
- Create: `backend/src/modules/directory/directory.gate.ts`
- Test: `backend/src/modules/directory/directory.gate.test.ts`

**Interfaces:**
- Consumes: `findMemberByUserId(db, userId)` from `@modules/member/member.repository` — returns the `Member` row whose `team_users` contains an ACTIVE row for this user, or `null`.
- Produces:
  - `DIRECTORY_DENY` — reason code constants
  - `assertDirectoryAccess(userId: bigint): Promise<{ memberId: bigint }>` — resolves, or throws `AppError` with `errorType: FORBIDDEN` and `details.reason`

- [ ] **Step 1: Write the constants file**

```ts
// backend/src/modules/directory/directory.constants.ts

/**
 * Why a caller was refused the directory.
 *
 * The code travels to the customer app so it can show the right call to action
 * — "pay now" is a different screen from "renew". It carries no member data,
 * which is the point: a refusal must not disclose what it is refusing.
 */
export const DIRECTORY_DENY = {
  /** Signed in, but this login belongs to no company at all. */
  NO_MEMBERSHIP: 'NO_MEMBERSHIP',
  /** Approved or still applying — the first invoice is not paid. */
  PAYMENT_PENDING: 'PAYMENT_PENDING',
  /** Term ended without renewal. */
  EXPIRED: 'EXPIRED',
  /** Withdrawn by the association. */
  SUSPENDED: 'SUSPENDED',
  /** The association has switched the directory off entirely. */
  DIRECTORY_OFF: 'DIRECTORY_OFF',
} as const;

export type DirectoryDenyReason = (typeof DIRECTORY_DENY)[keyof typeof DIRECTORY_DENY];

/** Rows per page. A hard server cap — `?limit=10000` still returns 24. */
export const DIRECTORY_PAGE_SIZE = 24;

/** How many category and city facets the filter dropdowns are given. */
export const DIRECTORY_FACET_LIMIT = 50;
```

- [ ] **Step 2: Write the failing test**

```ts
// backend/src/modules/directory/directory.gate.test.ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const findMemberByUserId = vi.fn();

vi.mock('@db/prisma', () => ({ prisma: {} }));
vi.mock('@modules/member/member.repository', () => ({
  findMemberByUserId: (...a: unknown[]) => findMemberByUserId(...a),
}));

const { assertDirectoryAccess } = await import('@modules/directory/directory.gate');
const { DIRECTORY_DENY } = await import('@modules/directory/directory.constants');

beforeEach(() => {
  vi.clearAllMocks();
});

/**
 * Holding a login is not membership. Anyone can complete the signup form in two
 * minutes; if that were the gate, the contact list would be free to whoever
 * asked, and every lapsed member would keep the benefit for ever.
 */
describe('assertDirectoryAccess', () => {
  it('admits an ACTIVE company', async () => {
    findMemberByUserId.mockResolvedValue({ id: 42n, status: 'ACTIVE' });

    await expect(assertDirectoryAccess(7n)).resolves.toEqual({ memberId: 42n });
  });

  it('refuses a login that belongs to no company', async () => {
    findMemberByUserId.mockResolvedValue(null);

    await expect(assertDirectoryAccess(7n)).rejects.toMatchObject({
      details: { reason: DIRECTORY_DENY.NO_MEMBERSHIP },
    });
  });

  it.each([
    ['DRAFT', DIRECTORY_DENY.PAYMENT_PENDING],
    ['PENDING', DIRECTORY_DENY.PAYMENT_PENDING],
    ['EXPIRED', DIRECTORY_DENY.EXPIRED],
    ['SUSPENDED', DIRECTORY_DENY.SUSPENDED],
    ['TERMINATED', DIRECTORY_DENY.EXPIRED],
  ])('refuses a %s company with reason %s', async (status, reason) => {
    findMemberByUserId.mockResolvedValue({ id: 42n, status });

    await expect(assertDirectoryAccess(7n)).rejects.toMatchObject({
      details: { reason },
    });
  });

  /*
    The status is re-read per call, never cached and never taken from a token.
    A member suspended five minutes ago must fail their next request, not wait
    for a token to expire.
  */
  it('re-reads the status on every call', async () => {
    findMemberByUserId.mockResolvedValue({ id: 42n, status: 'ACTIVE' });
    await assertDirectoryAccess(7n);
    await assertDirectoryAccess(7n);

    expect(findMemberByUserId).toHaveBeenCalledTimes(2);
  });

  it('never puts a company name in the refusal', async () => {
    findMemberByUserId.mockResolvedValue({
      id: 42n,
      status: 'EXPIRED',
      company_name: 'Kiran Traders',
    });

    const error = await assertDirectoryAccess(7n).catch((e: unknown) => e);

    expect(JSON.stringify(error)).not.toContain('Kiran Traders');
  });
});
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `cd backend && npx vitest run src/modules/directory/directory.gate.test.ts`
Expected: FAIL — `Cannot find module '@modules/directory/directory.gate'`

- [ ] **Step 4: Write the gate**

```ts
// backend/src/modules/directory/directory.gate.ts
import { ERROR_TYPES } from '@constant/errorTypes.constant';
import { prisma } from '@db/prisma';
import { findMemberByUserId } from '@modules/member/member.repository';
import { AppError } from '@utils/appError';

import { DIRECTORY_DENY, type DirectoryDenyReason } from './directory.constants';

/**
 * Who may open the member directory.
 *
 * The gate is the caller's own company status, not the presence of a token.
 * `DRAFT` and `PENDING` are the same refusal — both mean "has not paid" — and
 * `TERMINATED` is reported as `EXPIRED` because the customer app has nothing
 * different to offer a terminated company, and naming the distinction to the
 * browser tells it something the association may not want restated.
 */
const REASON_FOR_STATUS: Record<string, DirectoryDenyReason> = {
  DRAFT: DIRECTORY_DENY.PAYMENT_PENDING,
  PENDING: DIRECTORY_DENY.PAYMENT_PENDING,
  SUSPENDED: DIRECTORY_DENY.SUSPENDED,
  EXPIRED: DIRECTORY_DENY.EXPIRED,
  TERMINATED: DIRECTORY_DENY.EXPIRED,
};

export const directoryDenied = (reason: DirectoryDenyReason): AppError =>
  new AppError({
    errorType: ERROR_TYPES.FORBIDDEN,
    messageKey: 'directory.forbidden',
    details: { reason },
  });

export const assertDirectoryAccess = async (userId: bigint): Promise<{ memberId: bigint }> => {
  const member = await findMemberByUserId(prisma, userId);

  if (!member) throw directoryDenied(DIRECTORY_DENY.NO_MEMBERSHIP);

  if (member.status !== 'ACTIVE') {
    throw directoryDenied(REASON_FOR_STATUS[member.status] ?? DIRECTORY_DENY.NO_MEMBERSHIP);
  }

  return { memberId: member.id };
};
```

- [ ] **Step 5: Add the locale key**

In `backend/src/locales/en.json`, add under the existing top-level object:

```json
"directory": {
  "forbidden": "The member directory is available to active members."
}
```

- [ ] **Step 6: Run the test and confirm it passes**

Run: `cd backend && npx vitest run src/modules/directory/directory.gate.test.ts`
Expected: PASS — 8 tests

- [ ] **Step 7: Typecheck and lint**

Run: `cd backend && npm run typecheck && npm run lint`
Expected: both clean

- [ ] **Step 8: Commit**

```bash
cd backend
git add src/modules/directory src/locales/en.json
git commit -m "feat(directory): the viewer gate — ACTIVE membership, re-read per request"
```

---

## Task 2: Search indexes migration

**Files:**
- Create: `backend/prisma/migrations/<timestamp>_directory_search_indexes/migration.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: two indexes the repository's search and city filter rely on. No schema columns change.

- [ ] **Step 1: Create the migration without applying it**

Run: `cd backend && npx prisma migrate dev --create-only --name directory_search_indexes`
Expected: an empty migration directory is created. Prisma will report no schema drift — correct, since no model changes.

- [ ] **Step 2: Write the SQL**

Replace the generated `migration.sql` with:

```sql
-- Member directory search (docs/specs/2026-08-31-member-directory.md §6.3).
--
-- Both the trading name and the registered legal name are searchable; only the
-- trading name is ever displayed. A buyer who knows the registered name should
-- find the company, but publishing both invites impersonation.
CREATE INDEX IF NOT EXISTS "members_directory_fts_idx"
  ON "Members"
  USING GIN (
    to_tsvector(
      'english',
      coalesce("company_name", '') || ' ' ||
      coalesce("legal_name", '')  || ' ' ||
      coalesce("about", '')
    )
  );

-- The city / state filter reaches Members through the primary address.
CREATE INDEX IF NOT EXISTS "member_addresses_directory_city_idx"
  ON "MemberAddresses" ("city", "state")
  WHERE "is_primary" = true AND "deletedAt" IS NULL;
```

- [ ] **Step 3: Apply it**

Run: `cd backend && npm run prisma:migrate`
Expected: the migration applies; `npm run prisma:status` reports the database in sync.

- [ ] **Step 4: Confirm the indexes exist**

Run:
```bash
cd backend && npx prisma db execute --stdin <<'SQL'
SELECT indexname FROM pg_indexes
WHERE indexname IN ('members_directory_fts_idx', 'member_addresses_directory_city_idx');
SQL
```
Expected: both names listed.

- [ ] **Step 5: Commit**

```bash
cd backend
git add prisma/migrations
git commit -m "feat(directory): full-text and city indexes for directory search"
```

---

## Task 3: Repository and presenter

**Files:**
- Create: `backend/src/modules/directory/directory.repository.ts`
- Create: `backend/src/modules/directory/directory.presenter.ts`
- Create: `backend/src/modules/directory/directory.types.ts`
- Test: `backend/src/modules/directory/directory.leak.test.ts`

**Interfaces:**
- Consumes: `DIRECTORY_PAGE_SIZE`, `DIRECTORY_FACET_LIMIT` from Task 1's constants.
- Produces:
  - `DirectoryListQuery` — `{ q?: string; category?: string[]; city?: string; state?: string; page: number }`
  - `listDirectory(db, query)` → `{ rows: DirectoryRow[]; total: number }`
  - `findDirectoryMember(db, id)` → `DirectoryRow | null`
  - `presentCard(row)` / `presentProfile(row)` → the allowlisted shapes
  - `directorySlug(row)` → `string`

- [ ] **Step 1: Write the types**

```ts
// backend/src/modules/directory/directory.types.ts
import { z } from 'zod';

import { DIRECTORY_PAGE_SIZE } from './directory.constants';

/**
 * The listing query.
 *
 * `limit` is deliberately absent. The page size is the server's decision, not
 * the caller's — a directory that honours `?limit=10000` is a directory that
 * can be taken in one request.
 */
export const listDirectorySchema = z.object({
  q: z.string().trim().min(1).max(120).optional(),
  category: z.union([z.string(), z.array(z.string())]).optional(),
  city: z.string().trim().max(100).optional(),
  state: z.string().trim().max(100).optional(),
  page: z.coerce.number().int().min(1).max(500).default(1),
});

export const directorySlugSchema = z.object({
  slug: z
    .string()
    .trim()
    .min(1)
    .max(240)
    /* `<name>-<id>`; the id is what the lookup actually uses. */
    .regex(/-\d+$/, 'directory.badSlug'),
});

export type ListDirectoryQuery = z.infer<typeof listDirectorySchema>;

/** One row as the repository selects it. Nothing here that is not allowlisted. */
export interface DirectoryRow {
  id: bigint;
  company_name: string;
  member_code: string | null;
  about: string | null;
  website: string | null;
  logo_path: string | null;
  joined_on: Date | null;
  addresses: { city: string; state: string }[];
  contacts: {
    name: string;
    designation: string | null;
    email: string | null;
    phone: string | null;
  }[];
  categories: { category: { name: string } }[];
}

export interface DirectoryCard {
  slug: string;
  companyName: string;
  city: string | null;
  state: string | null;
  categories: string[];
  logoUrl: string | null;
}

export interface DirectoryProfile extends DirectoryCard {
  memberCode: string | null;
  joinedYear: number | null;
  website: string | null;
  about: string | null;
  contact: {
    name: string;
    designation: string | null;
    email: string | null;
    phone: string | null;
  } | null;
}

export { DIRECTORY_PAGE_SIZE };
```

- [ ] **Step 2: Write the repository**

```ts
// backend/src/modules/directory/directory.repository.ts
import { Prisma } from '@prisma/client';

import type { Db } from '@db/prisma';

import { DIRECTORY_FACET_LIMIT, DIRECTORY_PAGE_SIZE } from './directory.constants';
import type { DirectoryRow, ListDirectoryQuery } from './directory.types';

/**
 * The three switches, as one WHERE clause.
 *
 * Not a helper each caller is trusted to remember: a listed company must be
 * live, paid and consenting, and the only way to guarantee that is for every
 * read in this file to start from the same object.
 */
const LISTED = {
  deletedAt: null,
  status: 'ACTIVE',
  directory_visible: true,
} as const;

/** Exactly the allowlisted columns. `legal_name` is searched, never selected. */
const SELECT = {
  id: true,
  company_name: true,
  member_code: true,
  about: true,
  website: true,
  logo_path: true,
  joined_on: true,
  addresses: {
    where: { is_primary: true, deletedAt: null },
    select: { city: true, state: true },
    take: 1,
  },
  contacts: {
    where: { is_primary: true, deletedAt: null },
    select: { name: true, designation: true, email: true, phone: true },
    take: 1,
  },
  categories: { select: { category: { select: { name: true } } } },
} satisfies Prisma.MemberSelect;

const filters = (query: ListDirectoryQuery): Prisma.MemberWhereInput[] => {
  const where: Prisma.MemberWhereInput[] = [];

  if (query.q) {
    /*
      Trading name, registered name and description. `mode: 'insensitive'` uses
      the trigram-free path; the GIN index from the migration serves the same
      columns for the ranked case. Both names are searched, only one is shown.
    */
    where.push({
      OR: [
        { company_name: { contains: query.q, mode: 'insensitive' } },
        { legal_name: { contains: query.q, mode: 'insensitive' } },
        { about: { contains: query.q, mode: 'insensitive' } },
      ],
    });
  }

  const categories = query.category
    ? Array.isArray(query.category)
      ? query.category
      : [query.category]
    : [];

  if (categories.length) {
    where.push({ categories: { some: { category: { name: { in: categories } } } } });
  }

  if (query.city) {
    where.push({ addresses: { some: { is_primary: true, city: query.city, deletedAt: null } } });
  }

  if (query.state) {
    where.push({ addresses: { some: { is_primary: true, state: query.state, deletedAt: null } } });
  }

  return where;
};

export const listDirectory = async (
  db: Db,
  query: ListDirectoryQuery,
): Promise<{ rows: DirectoryRow[]; total: number }> => {
  const where: Prisma.MemberWhereInput = { ...LISTED, AND: filters(query) };

  const [rows, total] = await Promise.all([
    db.member.findMany({
      where,
      select: SELECT,
      orderBy: { company_name: 'asc' },
      skip: (query.page - 1) * DIRECTORY_PAGE_SIZE,
      take: DIRECTORY_PAGE_SIZE,
    }),
    db.member.count({ where }),
  ]);

  return { rows: rows as DirectoryRow[], total };
};

export const findDirectoryMember = async (db: Db, id: bigint): Promise<DirectoryRow | null> =>
  (await db.member.findFirst({ where: { ...LISTED, id }, select: SELECT })) as DirectoryRow | null;

/** Facets for the filter dropdowns, counted against what is actually listed. */
export const listCategoryFacets = (db: Db) =>
  db.membershipCategory.findMany({
    where: { is_active: true, members: { some: { member: { ...LISTED } } } },
    select: { name: true },
    orderBy: { display_order: 'asc' },
    take: DIRECTORY_FACET_LIMIT,
  });

export const listCityFacets = (db: Db) =>
  db.memberAddress.findMany({
    where: { is_primary: true, deletedAt: null, member: { ...LISTED } },
    select: { city: true, state: true },
    distinct: ['city', 'state'],
    orderBy: [{ state: 'asc' }, { city: 'asc' }],
    take: DIRECTORY_FACET_LIMIT,
  });
```

- [ ] **Step 3: Write the presenter**

```ts
// backend/src/modules/directory/directory.presenter.ts
import { API_V1, END_POINTS } from '@constant';

import type { DirectoryCard, DirectoryProfile, DirectoryRow } from './directory.types';

/**
 * What a member is allowed to see of another member.
 *
 * One allowlist, because only an ACTIVE member ever reaches this file — there
 * is no anonymous audience to have a second, narrower list for. An explicit
 * allowlist rather than "the row minus a few fields": the difference shows the
 * next time a column is added to `Members`, which an allowlist leaves out until
 * somebody decides otherwise.
 *
 * Absent by design, and not by accident: `gst_number`, `pan_number`,
 * `iec_code`, `trade_license_no`, every `MemberDocument`, the pincode and the
 * street lines, and `legal_name` — which is searched but never shown, because
 * publishing a company under two names invites impersonation.
 */

/** `<slug>-<id>`. The id is the identity; the words are for the reader. */
export const directorySlug = (row: Pick<DirectoryRow, 'id' | 'company_name'>): string => {
  const words = row.company_name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);

  return `${words || 'member'}-${row.id}`;
};

/** The id a slug addresses. `null` when the slug carries none. */
export const idFromSlug = (slug: string): bigint | null => {
  const match = /-(\d+)$/.exec(slug);

  return match ? BigInt(match[1]) : null;
};

/**
 * The logo's address — gated like everything else here. A public logo URL would
 * disclose that a given company is a member, and could be shared past the wall.
 */
const logoUrl = (row: DirectoryRow): string | null =>
  row.logo_path ? `${API_V1}${END_POINTS.DIRECTORY}/media/${row.id}` : null;

export const presentCard = (row: DirectoryRow): DirectoryCard => ({
  slug: directorySlug(row),
  companyName: row.company_name,
  city: row.addresses[0]?.city ?? null,
  state: row.addresses[0]?.state ?? null,
  categories: row.categories.map((link) => link.category.name),
  logoUrl: logoUrl(row),
});

export const presentProfile = (row: DirectoryRow): DirectoryProfile => {
  const contact = row.contacts[0] ?? null;

  return {
    ...presentCard(row),
    memberCode: row.member_code,
    /* The year, not the date. "Member since 2026" is the useful signal. */
    joinedYear: row.joined_on ? row.joined_on.getFullYear() : null,
    website: row.website,
    about: row.about,
    contact: contact
      ? {
          name: contact.name,
          designation: contact.designation,
          email: contact.email,
          phone: contact.phone,
        }
      : null,
  };
};
```

- [ ] **Step 4: Write the leak test**

```ts
// backend/src/modules/directory/directory.leak.test.ts
import { describe, expect, it } from 'vitest';

import { presentCard, presentProfile, directorySlug, idFromSlug } from '@modules/directory/directory.presenter';
import type { DirectoryRow } from '@modules/directory/directory.types';

/**
 * A full row, including every field that must never be published. The row is
 * deliberately fatter than `DirectoryRow` so the test proves the presenter
 * *selects*, rather than proving the repository happened not to fetch.
 */
const row = {
  id: 42n,
  company_name: 'Shreeji Exports Pvt Ltd',
  legal_name: 'Shreeji Overseas Trading Pvt Ltd',
  member_code: 'LGDGF/2026/0042',
  about: 'Spice and agri-commodity exporters since 1998.',
  website: 'https://shreejiexports.in',
  logo_path: 'members/42/logo.png',
  joined_on: new Date('2026-04-01T00:00:00Z'),
  gst_number: '24AABCS1234F1Z5',
  pan_number: 'AABCS1234F',
  iec_code: '0398012345',
  trade_license_no: 'TL-99',
  addresses: [{ city: 'Ahmedabad', state: 'Gujarat', pincode: '380009' }],
  contacts: [
    {
      name: 'Rakesh Patel',
      designation: 'Director',
      email: 'rakesh@shreejiexports.in',
      phone: '+91 98250 12345',
    },
  ],
  categories: [{ category: { name: 'Spices' } }, { category: { name: 'Agri Commodities' } }],
} as unknown as DirectoryRow;

describe('directory presenter', () => {
  it('returns exactly the allowlisted profile keys', () => {
    expect(Object.keys(presentProfile(row)).sort()).toEqual(
      [
        'about',
        'categories',
        'city',
        'companyName',
        'contact',
        'joinedYear',
        'logoUrl',
        'memberCode',
        'slug',
        'state',
        'website',
      ].sort(),
    );
  });

  it.each([
    ['GST', '24AABCS1234F1Z5'],
    ['PAN', 'AABCS1234F'],
    ['IEC', '0398012345'],
    ['trade licence', 'TL-99'],
    ['legal name', 'Shreeji Overseas'],
    ['pincode', '380009'],
    ['storage path', 'members/42/logo.png'],
  ])('never publishes the %s', (_label, secret) => {
    expect(JSON.stringify(presentProfile(row))).not.toContain(secret);
    expect(JSON.stringify(presentCard(row))).not.toContain(secret);
  });

  it('keeps contact details off the card, and on the profile', () => {
    expect(JSON.stringify(presentCard(row))).not.toContain('98250');
    expect(presentProfile(row).contact?.phone).toBe('+91 98250 12345');
  });

  it('publishes the joining year, not the date', () => {
    expect(presentProfile(row).joinedYear).toBe(2026);
    expect(JSON.stringify(presentProfile(row))).not.toContain('2026-04-01');
  });

  it('round-trips a slug back to its id', () => {
    const slug = directorySlug(row);

    expect(slug).toBe('shreeji-exports-pvt-ltd-42');
    expect(idFromSlug(slug)).toBe(42n);
  });

  it('reads the id from a stale slug, so a renamed company keeps its links', () => {
    expect(idFromSlug('whatever-the-old-name-was-42')).toBe(42n);
  });
});
```

- [ ] **Step 5: Run it**

Run: `cd backend && npx vitest run src/modules/directory/directory.leak.test.ts`
Expected: PASS — 12 assertions across 6 tests

- [ ] **Step 6: Typecheck, lint, commit**

```bash
cd backend
npm run typecheck && npm run lint
git add src/modules/directory
git commit -m "feat(directory): repository, presenter and the field allowlist"
```

---

## Task 4: Service, controller, routes and mounting

**Files:**
- Create: `backend/src/modules/directory/directory.service.ts`
- Create: `backend/src/modules/directory/directory.controller.ts`
- Create: `backend/src/modules/directory/directory.routes.ts`
- Test: `backend/src/modules/directory/directory.search.test.ts`
- Modify: `backend/src/helpers/settings.ts`
- Modify: `backend/src/routes/index.ts`

**Interfaces:**
- Consumes: `assertDirectoryAccess` (Task 1), the repository and presenter (Task 3), `getBooleanSetting` from `@helpers/settings`, `openPublicLogo` from `@modules/member/member.logo.service`.
- Produces: `directoryRouter` — mounted at `/api/v1/directory`.

- [ ] **Step 1: Add the setting key**

In `backend/src/helpers/settings.ts`, inside `SETTING_KEYS`, add:

```ts
  /** Whether the member directory is available at all. Off empties it for everyone. */
  DIRECTORY_ENABLED: 'directory.enabled',
```

- [ ] **Step 2: Write the service**

```ts
// backend/src/modules/directory/directory.service.ts
import { prisma } from '@db/prisma';
import { getBooleanSetting, SETTING_KEYS } from '@helpers/settings';
import { openPublicLogo } from '@modules/member/member.logo.service';

import { DIRECTORY_DENY, DIRECTORY_PAGE_SIZE } from './directory.constants';
import { assertDirectoryAccess, directoryDenied } from './directory.gate';
import { presentCard, presentProfile, idFromSlug } from './directory.presenter';
import * as repo from './directory.repository';
import type { ListDirectoryQuery } from './directory.types';

/**
 * Every entry point starts the same way: prove the caller is an ACTIVE member,
 * then prove the association has the directory switched on. Neither check is
 * something a caller can skip by choosing a different endpoint, which is why
 * they live here rather than in the controller.
 */
const open = async (userId: bigint): Promise<void> => {
  await assertDirectoryAccess(userId);

  if (!(await getBooleanSetting(SETTING_KEYS.DIRECTORY_ENABLED, true))) {
    throw directoryDenied(DIRECTORY_DENY.DIRECTORY_OFF);
  }
};

export const list = async (userId: bigint, query: ListDirectoryQuery) => {
  await open(userId);

  const { rows, total } = await repo.listDirectory(prisma, query);

  return {
    items: rows.map(presentCard),
    page: query.page,
    pageSize: DIRECTORY_PAGE_SIZE,
    total,
    totalPages: Math.max(1, Math.ceil(total / DIRECTORY_PAGE_SIZE)),
  };
};

export const detail = async (userId: bigint, slug: string) => {
  await open(userId);

  const id = idFromSlug(slug);

  if (id === null) return null;

  const row = await repo.findDirectoryMember(prisma, id);

  return row ? presentProfile(row) : null;
};

export const facets = async (userId: bigint) => {
  await open(userId);

  const [categories, cities] = await Promise.all([
    repo.listCategoryFacets(prisma),
    repo.listCityFacets(prisma),
  ]);

  return {
    categories: categories.map((row) => row.name),
    cities: cities.map((row) => ({ city: row.city, state: row.state })),
  };
};

/**
 * The logo, behind the same gate as everything else.
 *
 * `openPublicLogo` already enforces ACTIVE + `directory_visible` on the member
 * being fetched; the gate above enforces it on the member asking. Both halves
 * are needed — one says who may look, the other says who may be looked at.
 */
export const logo = async (userId: bigint, memberId: bigint) => {
  await open(userId);

  return openPublicLogo(memberId);
};
```

- [ ] **Step 3: Write the controller**

```ts
// backend/src/modules/directory/directory.controller.ts
import type { NextFunction, Request, RequestHandler, Response } from 'express';

import { ERROR_TYPES } from '@constant/errorTypes.constant';
import { RES_STATUS } from '@constant/message.constant';
import * as service from '@modules/directory/directory.service';
import { AppError } from '@utils/appError';
import { handleApiResponse } from '@utils/handleResponse';

const handler =
  (fn: (req: Request, res: Response) => Promise<void>): RequestHandler =>
  (req, res, next: NextFunction) => {
    void fn(req, res).catch(next);
  };

const callerId = (req: Request): bigint => {
  if (req.actor?.id === undefined) {
    throw new AppError({ errorType: ERROR_TYPES.UNAUTHORIZED, messageKey: 'auth.unauthorized' });
  }

  return BigInt(req.actor.id);
};

const notFound = (): AppError =>
  new AppError({ errorType: ERROR_TYPES.NOT_FOUND, messageKey: 'common.notFound' });

export const listDirectory = handler(async (req, res) => {
  const data = await service.list(callerId(req), req.query as never);

  handleApiResponse(res, { responseType: RES_STATUS.GET, data });
});

export const getDirectoryMember = handler(async (req, res) => {
  const data = await service.detail(callerId(req), String(req.params.slug));

  /*
    404 whether the company does not exist, is not ACTIVE, or opted out. A 403
    here would confirm which — that a given company is a member of this
    association is itself something the directory does not disclose.
  */
  if (!data) throw notFound();

  handleApiResponse(res, { responseType: RES_STATUS.GET, data });
});

export const getFilters = handler(async (req, res) => {
  const data = await service.facets(callerId(req));

  handleApiResponse(res, { responseType: RES_STATUS.GET, data });
});

export const serveDirectoryLogo = handler(async (req, res) => {
  const { stream, mime } = await service.logo(callerId(req), BigInt(String(req.params.id)));

  res.setHeader('Content-Type', mime);
  /* Private: this image is entitlement-gated, so no shared cache may hold it. */
  res.setHeader('Cache-Control', 'private, max-age=300');
  stream.pipe(res);
});
```

- [ ] **Step 4: Write the routes**

```ts
// backend/src/modules/directory/directory.routes.ts
import { Router } from 'express';

import { authenticate, validateRequest } from '@middleware';
import * as controller from '@modules/directory/directory.controller';
import { directorySlugSchema, listDirectorySchema } from '@modules/directory/directory.types';
import { idParamSchema } from '@modules/member/member.types';

/**
 * `/api/v1/directory` — the member directory. One router, and only one.
 *
 * There is deliberately no public sibling. News has both because an article is
 * written to be read by anyone; a member's contact details are not. Decision D1
 * (docs/client-decisions.md) made this members-only, so an anonymous audience
 * has no endpoint to reach rather than a narrower response to receive.
 *
 * `authenticate` proves there is a session. It does NOT prove membership —
 * `directory.gate.ts` does that, per request, from the database.
 */
export const directoryRouter = Router();

directoryRouter.use(authenticate);

directoryRouter.get(
  '/',
  validateRequest({ query: listDirectorySchema }),
  controller.listDirectory,
);

directoryRouter.get('/filters', controller.getFilters);

directoryRouter.get(
  '/media/:id',
  validateRequest({ params: idParamSchema }),
  controller.serveDirectoryLogo,
);

/* Last: a bare segment must not swallow `/filters` or `/media/:id`. */
directoryRouter.get(
  '/:slug',
  validateRequest({ params: directorySlugSchema }),
  controller.getDirectoryMember,
);
```

- [ ] **Step 5: Mount it**

In `backend/src/routes/index.ts`, add the import beside the other module imports:

```ts
import { directoryRouter } from '@modules/directory/directory.routes';
```

and the mount, after the news mounts:

```ts
// M9 — the member directory. Members-only by decision D1: one router, member
// token required, and the ACTIVE check inside. There is no public sibling.
router.use(`${END_POINTS.V1}${END_POINTS.DIRECTORY}`, directoryRouter);
```

- [ ] **Step 6: Write the search and cap test**

```ts
// backend/src/modules/directory/directory.search.test.ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const memberFindMany = vi.fn();
const memberCount = vi.fn();
const findMemberByUserId = vi.fn();
const getBooleanSetting = vi.fn();

vi.mock('@db/prisma', () => ({
  prisma: {
    member: {
      findMany: (...a: unknown[]) => memberFindMany(...a),
      count: (...a: unknown[]) => memberCount(...a),
    },
  },
}));
vi.mock('@modules/member/member.repository', () => ({
  findMemberByUserId: (...a: unknown[]) => findMemberByUserId(...a),
}));
vi.mock('@helpers/settings', async () => {
  const actual = await vi.importActual<typeof import('@helpers/settings')>('@helpers/settings');

  return { ...actual, getBooleanSetting: (...a: unknown[]) => getBooleanSetting(...a) };
});

const service = await import('@modules/directory/directory.service');

beforeEach(() => {
  vi.clearAllMocks();
  findMemberByUserId.mockResolvedValue({ id: 1n, status: 'ACTIVE' });
  getBooleanSetting.mockResolvedValue(true);
  memberFindMany.mockResolvedValue([]);
  memberCount.mockResolvedValue(0);
});

describe('directory listing', () => {
  it('only ever lists live, ACTIVE, consenting companies', async () => {
    await service.list(7n, { page: 1 });

    const where = memberFindMany.mock.calls[0][0].where as Record<string, unknown>;

    expect(where).toMatchObject({
      deletedAt: null,
      status: 'ACTIVE',
      directory_visible: true,
    });
  });

  it('caps the page at 24 rows however the caller asks', async () => {
    await service.list(7n, { page: 1, limit: 10000 } as never);

    expect(memberFindMany.mock.calls[0][0].take).toBe(24);
  });

  it('searches the trading name, the legal name and the description', async () => {
    await service.list(7n, { q: 'spices', page: 1 });

    const and = (memberFindMany.mock.calls[0][0].where as { AND: { OR?: unknown[] }[] }).AND;
    const or = JSON.stringify(and.find((clause) => clause.OR)?.OR);

    expect(or).toContain('company_name');
    expect(or).toContain('legal_name');
    expect(or).toContain('about');
  });

  it('treats an injection string as an ordinary search term', async () => {
    await service.list(7n, { q: "'; DROP TABLE \"Members\"; --", page: 1 });

    expect(memberFindMany).toHaveBeenCalledTimes(1);
    expect(memberCount).toHaveBeenCalledTimes(1);
  });

  it('refuses everyone when the association switches the directory off', async () => {
    getBooleanSetting.mockResolvedValue(false);

    await expect(service.list(7n, { page: 1 })).rejects.toMatchObject({
      details: { reason: 'DIRECTORY_OFF' },
    });
    expect(memberFindMany).not.toHaveBeenCalled();
  });

  /*
    Looking and being listed are different questions. A member who opted out
    still pays, and still gets the benefit they paid for.
  */
  it('lets a member who opted out of being listed still search', async () => {
    findMemberByUserId.mockResolvedValue({ id: 1n, status: 'ACTIVE', directory_visible: false });

    await expect(service.list(7n, { page: 1 })).resolves.toMatchObject({ total: 0 });
  });

  it('refuses a PENDING company before it queries anything', async () => {
    findMemberByUserId.mockResolvedValue({ id: 1n, status: 'PENDING' });

    await expect(service.list(7n, { page: 1 })).rejects.toMatchObject({
      details: { reason: 'PAYMENT_PENDING' },
    });
    expect(memberFindMany).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 7: Run the whole directory suite**

Run: `cd backend && npx vitest run src/modules/directory`
Expected: PASS — gate, leak and search suites all green

- [ ] **Step 8: Run the full backend suite, typecheck and lint**

Run: `cd backend && npm run typecheck && npm run lint && npx vitest run`
Expected: all clean; the previously passing 220 tests still pass

- [ ] **Step 9: Commit**

```bash
cd backend
git add src/modules/directory src/helpers/settings.ts src/routes/index.ts
git commit -m "feat(directory): member-only listing, profile, facets and gated logo"
```

---

## Task 5: Customer — service, endpoints, and removing the public route

**Files:**
- Create: `customer/src/services/DirectoryService.ts`
- Modify: `customer/src/constants/endpoints.ts`
- **Delete:** `customer/src/app/(public)/directory/page.tsx`

**Interfaces:**
- Consumes: `ApiService.get<T>(url, config?)`, `ENDPOINTS`.
- Produces: `DirectoryService.list`, `.detail`, `.filters`; types `DirectoryCard`, `DirectoryProfile`, `DirectoryDenyReason`.

- [ ] **Step 1: Delete the public placeholder**

```bash
cd customer && rm "src/app/(public)/directory/page.tsx" && rmdir "src/app/(public)/directory"
```

This is the point of the module: the route must not exist on the public side. Deleting it is not tidying — it is the deliverable.

- [ ] **Step 2: Add the endpoints**

In `customer/src/constants/endpoints.ts`, after the M9 news block:

```ts
  /* --- M9 member directory (members-only, decision D1) --------------------- */
  /* There is deliberately no `publicDirectory`. An anonymous caller has no
     endpoint here — not a narrower response, no endpoint at all. */
  directory: '/directory',
  directoryFilters: '/directory/filters',
  directoryMember: (slug: string) => `/directory/${slug}`,
```

- [ ] **Step 3: Write the service**

```ts
// customer/src/services/DirectoryService.ts
'use client';

import { ENDPOINTS } from '@/constants/endpoints';

import ApiService from './ApiService';

/**
 * The member directory. Mirrors `backend/src/modules/directory`.
 *
 * No `skipAuth` anywhere in this file, unlike `SiteService`: every call here
 * requires a session, and a caller without one should take the normal
 * refresh-and-redirect path rather than silently receive nothing.
 */

/** Why the server refused. Drives which lock screen the member sees. */
export type DirectoryDenyReason =
  | 'NO_MEMBERSHIP'
  | 'PAYMENT_PENDING'
  | 'EXPIRED'
  | 'SUSPENDED'
  | 'DIRECTORY_OFF';

export interface DirectoryCard {
  slug: string;
  companyName: string;
  city: string | null;
  state: string | null;
  categories: string[];
  /** API-relative; run it through `mediaUrl` before putting it in an `<img>`. */
  logoUrl: string | null;
}

export interface DirectoryProfile extends DirectoryCard {
  memberCode: string | null;
  joinedYear: number | null;
  website: string | null;
  about: string | null;
  contact: {
    name: string;
    designation: string | null;
    email: string | null;
    phone: string | null;
  } | null;
}

export interface DirectoryPage {
  items: DirectoryCard[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
}

export interface DirectoryFilters {
  categories: string[];
  cities: { city: string; state: string }[];
}

export interface DirectoryQuery {
  q?: string;
  category?: string[];
  city?: string;
  page?: number;
}

const params = (query: DirectoryQuery): URLSearchParams => {
  const search = new URLSearchParams();

  if (query.q) search.set('q', query.q);
  if (query.city) search.set('city', query.city);
  if (query.page && query.page > 1) search.set('page', String(query.page));
  query.category?.forEach((name) => search.append('category', name));

  return search;
};

export const DirectoryService = {
  list: (query: DirectoryQuery = {}) => {
    const search = params(query).toString();

    return ApiService.get<DirectoryPage>(
      search ? `${ENDPOINTS.directory}?${search}` : ENDPOINTS.directory,
    );
  },
  detail: (slug: string) => ApiService.get<DirectoryProfile>(ENDPOINTS.directoryMember(slug)),
  filters: () => ApiService.get<DirectoryFilters>(ENDPOINTS.directoryFilters),
};

export default DirectoryService;
```

- [ ] **Step 4: Verify the public route is gone**

Run:
```bash
cd customer && test ! -e "src/app/(public)/directory" && echo "public directory route absent — correct"
```
Expected: the message prints.

- [ ] **Step 5: Typecheck and lint**

Run: `cd customer && npm run typecheck && npx next lint`
Expected: both clean

- [ ] **Step 6: Commit**

```bash
cd customer
git add src/services/DirectoryService.ts src/constants/endpoints.ts
git add -A "src/app/(public)"
git commit -m "feat(directory): member directory client; remove the public route"
```

---

## Task 6: Customer — the lock screen

Build this **before** the list. It is the screen most people will see, and it is where the module earns its fee.

**Files:**
- Create: `customer/src/components/directory/DirectoryLock.tsx`

**Interfaces:**
- Consumes: `DirectoryDenyReason` from Task 5.
- Produces: `<DirectoryLock reason={...} />`, and `denyReasonOf(error): DirectoryDenyReason | null`.

- [ ] **Step 1: Write the component**

```tsx
// customer/src/components/directory/DirectoryLock.tsx
'use client';

import Link from 'next/link';

import Button from '@/components/ui/Button';
import Card from '@/components/ui/Card';
import type { DirectoryDenyReason } from '@/services/DirectoryService';

/**
 * What a member who cannot open the directory is told.
 *
 * This is not an error state. It is the clearest statement of value the portal
 * makes: it names what is behind the wall, says exactly why the reader is not
 * through it, and puts the one action that fixes that directly underneath.
 *
 * It never names a company, never counts what is inside beyond the association's
 * own published member total, and never lists anything — a refusal that
 * discloses what it is refusing is not a refusal.
 */

interface LockCopy {
  title: string;
  body: string;
  action: { label: string; href: string } | null;
}

const COPY: Record<DirectoryDenyReason, LockCopy> = {
  NO_MEMBERSHIP: {
    title: 'The member directory is for members',
    body: 'Members can search every listed company and contact them directly.',
    action: { label: 'Become a member', href: '/signup' },
  },
  PAYMENT_PENDING: {
    title: 'The directory unlocks when you join',
    body: 'Your membership is pending payment. Once your invoice is paid you can search every listed member and contact them directly.',
    action: { label: 'Pay now', href: '/invoices' },
  },
  EXPIRED: {
    title: 'Your membership has expired',
    body: 'Renew to search the directory and contact members again.',
    action: { label: 'Renew membership', href: '/invoices' },
  },
  SUSPENDED: {
    title: 'Your membership is suspended',
    body: 'Directory access is paused while your membership is suspended. Please contact the association.',
    action: { label: 'Contact the association', href: '/contact' },
  },
  /* Not the member's fault and not theirs to fix, so no action button. */
  DIRECTORY_OFF: {
    title: 'The directory is temporarily unavailable',
    body: 'The association has paused the member directory. Please check back shortly.',
    action: null,
  },
};

/** The reason code the API sent, when it sent one. */
export const denyReasonOf = (error: unknown): DirectoryDenyReason | null => {
  const reason = (
    error as { response?: { data?: { details?: { reason?: string } } } } | undefined
  )?.response?.data?.details?.reason;

  return reason && reason in COPY ? (reason as DirectoryDenyReason) : null;
};

export default function DirectoryLock({ reason }: { reason: DirectoryDenyReason }) {
  const copy = COPY[reason];

  return (
    <Card className="mx-auto max-w-xl text-center">
      <div className="flex flex-col items-center gap-4 p-8">
        <span aria-hidden className="text-3xl">
          🔒
        </span>
        <h1 className="text-heading text-fg">{copy.title}</h1>
        <p className="text-supporting text-fg-muted">{copy.body}</p>
        {copy.action ? (
          <Button asChild>
            <Link href={copy.action.href}>{copy.action.label}</Link>
          </Button>
        ) : null}
      </div>
    </Card>
  );
}
```

- [ ] **Step 2: Confirm `Button` supports `asChild`**

Run: `cd customer && grep -n "asChild" src/components/ui/Button.tsx`
Expected: a match. **If there is no match**, replace the `<Button asChild>` block with:

```tsx
        <Link href={copy.action.href} className="btn btn-primary">
          {copy.action.label}
        </Link>
```

- [ ] **Step 3: Typecheck, lint, commit**

```bash
cd customer
npm run typecheck && npx next lint
git add src/components/directory
git commit -m "feat(directory): the lock screen, per refusal reason"
```

---

## Task 7: Customer — the list and profile pages

**Files:**
- Create: `customer/src/app/(member)/directory/page.tsx`
- Create: `customer/src/app/(member)/directory/[slug]/page.tsx`
- Create: `customer/src/components/directory/DirectoryList.tsx`
- Create: `customer/src/components/directory/DirectoryProfileView.tsx`

**Interfaces:**
- Consumes: `DirectoryService`, `DirectoryLock`, `denyReasonOf`, `mediaUrl`.
- Produces: the two routed screens.

- [ ] **Step 1: Write the list component**

```tsx
// customer/src/components/directory/DirectoryList.tsx
'use client';

import Link from 'next/link';
import { useCallback, useEffect, useState } from 'react';

import Card from '@/components/ui/Card';
import ErrorState from '@/components/ui/ErrorState';
import Skeleton from '@/components/ui/Skeleton';
import DirectoryLock, { denyReasonOf } from '@/components/directory/DirectoryLock';
import DirectoryService, {
  type DirectoryDenyReason,
  type DirectoryFilters,
  type DirectoryPage,
} from '@/services/DirectoryService';
import { mediaUrl } from '@/utils/mediaUrl';

/**
 * C-04 — the member directory.
 *
 * Current state: you are searching the association's listed member companies.
 * Required action: search by name, category or city.
 * Next step: open a company to see who to contact.
 * Expected result: you reach the member you were looking for.
 */

export default function DirectoryList() {
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState('');
  const [city, setCity] = useState('');
  const [page, setPage] = useState(1);

  const [data, setData] = useState<DirectoryPage | null>(null);
  const [filters, setFilters] = useState<DirectoryFilters | null>(null);
  const [denied, setDenied] = useState<DirectoryDenyReason | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await DirectoryService.list({
        q: query || undefined,
        category: category ? [category] : undefined,
        city: city || undefined,
        page,
      });

      setData(result);
      setDenied(null);
    } catch (caught) {
      const reason = denyReasonOf(caught);

      if (reason) setDenied(reason);
      else setError(caught);
    } finally {
      setLoading(false);
    }
  }, [query, category, city, page]);

  useEffect(() => {
    /* Debounced so typing does not fire a request per keystroke. */
    const timer = setTimeout(() => void load(), 250);

    return () => clearTimeout(timer);
  }, [load]);

  useEffect(() => {
    DirectoryService.filters()
      .then(setFilters)
      /* A failed facet load is not a failed page — the search box still works. */
      .catch(() => setFilters(null));
  }, []);

  if (denied) return <DirectoryLock reason={denied} />;

  if (loading && !data) return <Skeleton variant="list" />;

  if (error) {
    return (
      <ErrorState
        title="We could not load the directory"
        description="Try again, and if it keeps happening, quote the reference below."
        onRetry={() => void load()}
      />
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-heading text-fg">Member directory</h1>
        <p className="text-supporting text-fg-muted">{data?.total ?? 0} members</p>
      </header>

      <div className="flex flex-wrap gap-2">
        <input
          aria-label="Search members"
          className="input flex-1"
          placeholder="Search by company name"
          value={query}
          onChange={(event) => {
            setPage(1);
            setQuery(event.target.value);
          }}
        />
        <select
          aria-label="Filter by category"
          className="input"
          value={category}
          onChange={(event) => {
            setPage(1);
            setCategory(event.target.value);
          }}
        >
          <option value="">All categories</option>
          {filters?.categories.map((name) => (
            <option key={name} value={name}>
              {name}
            </option>
          ))}
        </select>
        <select
          aria-label="Filter by city"
          className="input"
          value={city}
          onChange={(event) => {
            setPage(1);
            setCity(event.target.value);
          }}
        >
          <option value="">All cities</option>
          {filters?.cities.map((place) => (
            <option key={`${place.city}-${place.state}`} value={place.city}>
              {place.city}, {place.state}
            </option>
          ))}
        </select>
      </div>

      {data && data.items.length === 0 ? (
        <Card>
          <p className="p-6 text-center text-supporting text-fg-muted">
            No members match that search. Try a different name, category or city.
          </p>
        </Card>
      ) : null}

      <ul className="grid gap-3 sm:grid-cols-2">
        {data?.items.map((member) => (
          <li key={member.slug}>
            <Link href={`/directory/${member.slug}`}>
              <Card className="flex h-full items-center gap-3 p-4">
                {member.logoUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    alt=""
                    className="h-12 w-12 rounded object-contain"
                    src={mediaUrl(member.logoUrl) ?? ''}
                  />
                ) : (
                  <span
                    aria-hidden
                    className="flex h-12 w-12 items-center justify-center rounded bg-surface-2 text-fg-muted"
                  >
                    {member.companyName.charAt(0)}
                  </span>
                )}
                <span className="flex flex-col">
                  <span className="text-fg">{member.companyName}</span>
                  <span className="text-supporting text-fg-muted">
                    {[member.city, member.state].filter(Boolean).join(', ')}
                  </span>
                  <span className="text-supporting text-fg-muted">
                    {member.categories.join(' · ')}
                  </span>
                </span>
              </Card>
            </Link>
          </li>
        ))}
      </ul>

      {data && data.totalPages > 1 ? (
        <nav className="flex items-center justify-center gap-3" aria-label="Pagination">
          <button
            className="btn"
            disabled={page <= 1}
            onClick={() => setPage((current) => current - 1)}
            type="button"
          >
            Previous
          </button>
          <span className="text-supporting text-fg-muted">
            Page {data.page} of {data.totalPages}
          </span>
          <button
            className="btn"
            disabled={page >= data.totalPages}
            onClick={() => setPage((current) => current + 1)}
            type="button"
          >
            Next
          </button>
        </nav>
      ) : null}
    </div>
  );
}
```

- [ ] **Step 2: Write the profile component**

```tsx
// customer/src/components/directory/DirectoryProfileView.tsx
'use client';

import { useEffect, useState } from 'react';

import Card from '@/components/ui/Card';
import ErrorState from '@/components/ui/ErrorState';
import Skeleton from '@/components/ui/Skeleton';
import DirectoryLock, { denyReasonOf } from '@/components/directory/DirectoryLock';
import DirectoryService, {
  type DirectoryDenyReason,
  type DirectoryProfile,
} from '@/services/DirectoryService';
import { mediaUrl } from '@/utils/mediaUrl';

/**
 * One member company.
 *
 * The contact block is the reason this screen exists. Everything above it is
 * how the reader confirms they have the right company; the phone number is what
 * they came for.
 */
export default function DirectoryProfileView({ slug }: { slug: string }) {
  const [member, setMember] = useState<DirectoryProfile | null>(null);
  const [denied, setDenied] = useState<DirectoryDenyReason | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let live = true;

    DirectoryService.detail(slug)
      .then((data) => {
        if (live) setMember(data);
      })
      .catch((caught: unknown) => {
        if (!live) return;
        const reason = denyReasonOf(caught);

        if (reason) setDenied(reason);
        else setError(caught);
      })
      .finally(() => {
        if (live) setLoading(false);
      });

    return () => {
      live = false;
    };
  }, [slug]);

  if (denied) return <DirectoryLock reason={denied} />;

  if (loading) return <Skeleton variant="card" />;

  if (error || !member) {
    return (
      <ErrorState
        title="We could not find that member"
        description="They may have left the directory, or the link may be out of date."
      />
    );
  }

  return (
    <Card>
      <div className="flex flex-col gap-6 p-6">
        <header className="flex items-center gap-4">
          {member.logoUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              alt=""
              className="h-16 w-16 rounded object-contain"
              src={mediaUrl(member.logoUrl) ?? ''}
            />
          ) : null}
          <div>
            <h1 className="text-heading text-fg">{member.companyName}</h1>
            <p className="text-supporting text-fg-muted">
              {[member.memberCode, member.joinedYear ? `Member since ${member.joinedYear}` : null]
                .filter(Boolean)
                .join(' · ')}
            </p>
            <p className="text-supporting text-fg-muted">
              {[member.city, member.state].filter(Boolean).join(', ')}
            </p>
          </div>
        </header>

        {member.about ? <p className="text-fg">{member.about}</p> : null}

        <dl className="grid gap-2 sm:grid-cols-2">
          <div>
            <dt className="text-supporting text-fg-muted">Business</dt>
            <dd className="text-fg">{member.categories.join(' · ') || '—'}</dd>
          </div>
          {member.website ? (
            <div>
              <dt className="text-supporting text-fg-muted">Website</dt>
              <dd>
                <a
                  className="link"
                  href={member.website}
                  rel="noopener noreferrer nofollow"
                  target="_blank"
                >
                  {member.website}
                </a>
              </dd>
            </div>
          ) : null}
        </dl>

        <section className="border-t pt-4">
          <h2 className="text-supporting text-fg-muted">Contact</h2>
          {member.contact ? (
            <div className="mt-2 flex flex-col gap-1">
              <p className="text-fg">
                {member.contact.name}
                {member.contact.designation ? `, ${member.contact.designation}` : ''}
              </p>
              {member.contact.phone ? (
                <a className="link" href={`tel:${member.contact.phone}`}>
                  {member.contact.phone}
                </a>
              ) : null}
              {member.contact.email ? (
                <a className="link" href={`mailto:${member.contact.email}`}>
                  {member.contact.email}
                </a>
              ) : null}
            </div>
          ) : (
            <p className="mt-2 text-supporting text-fg-muted">
              This member has not published a contact person.
            </p>
          )}
        </section>
      </div>
    </Card>
  );
}
```

- [ ] **Step 3: Write the two routed pages**

```tsx
// customer/src/app/(member)/directory/page.tsx
import type { Metadata } from 'next';

import DirectoryList from '@/components/directory/DirectoryList';

/*
  `noindex` belongs here as well as in robots. The route sits behind the member
  layout's auth guard, but a metadata directive costs nothing and covers the
  case where a crawler is somehow handed a rendered page.
*/
export const metadata: Metadata = {
  title: 'Member directory',
  robots: { index: false, follow: false },
};

export default function DirectoryPage() {
  return <DirectoryList />;
}
```

```tsx
// customer/src/app/(member)/directory/[slug]/page.tsx
import type { Metadata } from 'next';

import DirectoryProfileView from '@/components/directory/DirectoryProfileView';

export const metadata: Metadata = {
  title: 'Member',
  robots: { index: false, follow: false },
};

export default function DirectoryMemberPage({ params }: { params: { slug: string } }) {
  return <DirectoryProfileView slug={params.slug} />;
}
```

- [ ] **Step 4: Add the nav entry**

Find the member navigation list (`grep -rn "Invoices" customer/src/components --include=*.tsx | grep -i nav`) and add, after Events:

```tsx
  { label: 'Directory', href: '/directory' },
```

Match the surrounding entries' exact shape — if they carry an icon, give this one an icon too.

- [ ] **Step 5: Confirm the directory is in no sitemap**

Run: `cd customer && grep -rn "directory" src/app/sitemap.ts src/app/robots.ts 2>/dev/null; echo "exit $? — 1 means absent, which is correct"`
Expected: no `directory` entry in either file. **If one appears, remove it.**

- [ ] **Step 6: Typecheck, lint, build**

Run: `cd customer && npm run typecheck && npx next lint && npm run build`
Expected: all clean; the build output lists `/directory` and `/directory/[slug]` as dynamic routes.

- [ ] **Step 7: Commit**

```bash
cd customer
git add src/app/\(member\)/directory src/components/directory
git commit -m "feat(directory): member list, profile and navigation"
```

---

## Task 8: Customer — the member's own listing control

**Files:**
- Modify: `customer/src/app/(member)/profile/page.tsx` and its profile form component

**Interfaces:**
- Consumes: `MemberService.updateProfile` (existing), the `directory_visible` and `about` fields on `PATCH /members/me`.
- Produces: nothing new.

- [ ] **Step 1: Confirm the backend accepts both fields**

Run: `cd backend && grep -n "directory_visible\|about" src/modules/member/member.types.ts`
Expected: both appear in `updateProfileSchema`. **If either is missing**, add it there first:

```ts
  directory_visible: z.boolean().optional(),
  about: z.string().trim().max(2000).optional(),
```

then re-run `npm run typecheck` and commit that change on its own.

- [ ] **Step 2: Add the control to the profile form**

Inside the existing profile form, add a section. Match the file's existing field markup rather than the classes below if they differ:

```tsx
<section className="flex flex-col gap-2 border-t pt-4">
  <h2 className="text-supporting text-fg-muted">Directory listing</h2>

  <label className="flex items-start gap-2">
    <input
      checked={form.directory_visible}
      onChange={(event) =>
        setForm((current) => ({ ...current, directory_visible: event.target.checked }))
      }
      type="checkbox"
    />
    <span>
      <span className="text-fg">List my company in the member directory</span>
      <span className="block text-supporting text-fg-muted">
        Other active members can find your company and see your contact details. Your GST, PAN and
        documents are never shown.
      </span>
    </span>
  </label>

  <label className="flex flex-col gap-1">
    <span className="text-supporting text-fg-muted">About your company</span>
    <textarea
      className="input"
      maxLength={2000}
      onChange={(event) => setForm((current) => ({ ...current, about: event.target.value }))}
      placeholder="What your company does, in a sentence or two."
      rows={3}
      value={form.about ?? ''}
    />
  </label>

  {/*
    The effective state, not just the tick-box. A member who has opted in but
    whose membership lapsed is not listed, and saying "listed" would be a lie.
  */}
  <p className="text-supporting text-fg-muted">
    {member.status !== 'ACTIVE'
      ? 'Hidden — your membership is not active.'
      : form.directory_visible
        ? 'Listed — active members can find your company.'
        : 'Hidden — you have opted out.'}
  </p>
</section>
```

- [ ] **Step 3: Verify by hand**

Run `npm run dev` in `customer/`, sign in as an ACTIVE member, and check:
1. The tick-box reflects the saved value on load.
2. Unticking and saving, then reloading `/directory` from **another** active member's session, no longer shows that company.
3. The member who opted out can still open `/directory` and search — looking and being listed are separate.

- [ ] **Step 4: Typecheck, lint, commit**

```bash
cd customer
npm run typecheck && npx next lint
git add src/app/\(member\)/profile src/components
git commit -m "feat(directory): member controls their own listing and description"
```

---

## Task 9: Admin — the column and the switch

**Files:**
- Modify: `admin/src/pages/applications/ApplicationQueue.tsx` — the member-company scope is the members list (`/members` redirects to `/applications?scope=member-company`)
- Modify: `admin/src/pages/settings/SystemSettings.tsx`
- Modify: `admin/src/pages/members/ProfileTab.tsx` — the admin force-hide toggle

**Interfaces:**
- Consumes: the existing queue row type and settings form.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Read the UI catalogue first**

**REQUIRED:** invoke the `association-admin-ui` skill before touching any admin screen. It is the catalogue every screen is assembled from, and the reason a new column looks like the existing ones. Do not import Ant Design directly.

- [ ] **Step 2: Confirm the API returns what the column needs**

The column needs `status` and `directory_visible` per row. Run:

```bash
cd backend && grep -n "directory_visible" src/modules/member/member.repository.ts
```

**If the queue's select does not include `directory_visible`**, add it to the member-company scope's `select`, run `npm run typecheck`, and commit that on its own before continuing.

- [ ] **Step 3: Add the column**

In `ApplicationQueue.tsx`, beside the existing `status` column, matching its shape exactly:

```tsx
      {
        title: 'In directory',
        dataIndex: 'directory_visible',
        key: 'directory_visible',
        width: 150,
        /*
          Read-only, and it explains rather than controls. Three switches decide
          whether a company is listed and only one of them is the association's;
          a column that let staff toggle it would imply otherwise.
        */
        render: (_: unknown, row: ApplicationQueueRow) => {
          if (row.status !== 'ACTIVE') {
            return <span className="text-supporting text-fg-muted">Hidden — not active</span>;
          }

          return row.directory_visible ? (
            <span className="text-supporting text-fg">Listed</span>
          ) : (
            <span className="text-supporting text-fg-muted">Hidden — member&rsquo;s choice</span>
          );
        },
      },
```

- [ ] **Step 4: Add the settings switch**

In `SystemSettings.tsx`, add a boolean field for `directory.enabled`, matching the file's existing boolean fields:

```tsx
{
  key: 'directory.enabled',
  label: 'Member directory',
  help: 'When off, no member can open the directory. Individual listings are unaffected.',
  type: 'boolean',
  default: true,
}
```

- [ ] **Step 5: Seed the setting**

In the backend seed, add the row so a fresh database has it:

```ts
{
  key: 'directory.enabled',
  value: 'true',
  value_type: 'BOOLEAN',
  group: 'directory',
  description: 'Whether the member directory is available to members at all.',
  is_public: false,
},
```

`is_public: false` matters — this key must not reach the public settings endpoint.

- [ ] **Step 6: Verify**

Run: `cd admin && npm run typecheck && npm run lint && npm run build`
Expected: all clean.

Then by hand: switch `directory.enabled` off in admin, reload `/directory` as an ACTIVE member, and confirm the "temporarily unavailable" lock screen appears. Switch it back on.

- [ ] **Step 7: Commit**

```bash
cd admin
git add src/pages
git commit -m "feat(directory): in-directory column and the global directory switch"
```

---

## Task 10: End-to-end verification

**Files:** none created. This task is proof, not code.

- [ ] **Step 1: Full backend suite**

Run: `cd backend && npm run typecheck && npm run lint && npx vitest run`
Expected: all green, including the 220 tests that passed before this work.

- [ ] **Step 2: The anonymous check, against a running server**

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8000/api/v1/directory
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8000/api/v1/public/directory
```
Expected: `401` for the first, `404` for the second. **A 200 from either is a failed implementation.**

- [ ] **Step 3: The non-active check**

With a `PENDING` member's token:

```bash
curl -s -H "Authorization: Bearer $PENDING_TOKEN" http://localhost:8000/api/v1/directory
```
Expected: HTTP 403, and the body contains `"reason":"PAYMENT_PENDING"` and **no company name**.

- [ ] **Step 4: The active check**

With an `ACTIVE` member's token, request a listed company's profile and confirm the body:
- contains the contact phone and email
- contains **no** `gst`, `pan`, `iec`, `legal_name`, `pincode` or `logo_path`

- [ ] **Step 5: Both customer and admin build**

Run: `cd customer && npm run build` and `cd admin && npm run build`
Expected: both succeed. The customer build must **not** list a `/directory` route under the public segment.

- [ ] **Step 6: Update the status doc**

In `docs/implementation-status.md`, set M9's row to reflect the directory being built, and note that OQ-7 is answered. While there, correct the stale rows this plan's author observed: **M5 is built** (invoices and payments live in `modules/member`), and **M7 Events is built**.

- [ ] **Step 7: Final commit**

```bash
git add docs/implementation-status.md
git commit -m "docs(m9): member directory built; correct stale M5 and M7 statuses"
```

---

## Self-Review Notes

**Spec coverage.** Every section of `docs/specs/2026-08-31-member-directory.md` maps to a task: §2.2 the gate → Task 1 · §3 the three switches → Tasks 1, 4, 9 · §5 the allowlist → Task 3 · §6.1 routes → Task 4 · §6.3 search and cap → Tasks 2, 4 · §6.4 slugs → Task 3 · §7 customer screens → Tasks 5–8 · §8 admin → Task 9 · §9 migration → Task 2 · §10 tests → Tasks 1, 3, 4, 10.

**The two spec questions left open** (DIR-1 list an empty profile; DIR-2 notify on opt-out) are implemented as their stated assumptions: an empty profile **is** listed, because the base filter has no completeness condition; no notification is sent, because no task adds one. Both are reversible in one place if the association decides otherwise.

**Deliberately not in this plan**, per spec §11: per-profile view permissions, member-to-member messaging, enquiry forms, featured placement, member-facing Excel export, and any public or SEO surface.

**A note on Task 5's deletion.** Removing `(public)/directory/page.tsx` is the one destructive step here, and it is the deliverable rather than housekeeping — the whole decision is that this route must not exist publicly. It is a placeholder with no logic; nothing is lost.
