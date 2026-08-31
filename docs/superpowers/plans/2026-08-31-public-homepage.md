# Public Homepage Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce the client's supplied homepage design exactly inside the Next.js customer app, with events, news, member counts, member names and member countries driven by the backend API and the remaining figures held as static constants.

**Architecture:** The reference stylesheet is ported once into a single scoped stylesheet (`site.css`, every selector prefixed with `.da`) imported by the public layout, so the design cannot leak into member screens or fight Tailwind preflight. The reference's inline `<script>` is split into pure helper modules (`src/utils/home/*`) plus thin client components that own the DOM effects. A new read-only backend endpoint `GET /api/v1/public/site/stats` supplies the four dynamic values. Static copy and static figures live in one constants file.

**Tech Stack:** Next.js 14 App Router, TypeScript, Tailwind (for everything outside the ported stylesheet), Express + Prisma + PostgreSQL, vitest (backend only).

**Spec:** [`docs/superpowers/specs/2026-08-31-public-homepage-design.md`](../specs/2026-08-31-public-homepage-design.md)
**Reference design:** [`docs/superpowers/specs/2026-08-31-public-homepage-reference.html`](../specs/2026-08-31-public-homepage-reference.html)

---

## Global Constraints

These apply to **every** task. Read them before starting any task.

1. **The reference HTML is the source of truth for design.** When this plan and
   `2026-08-31-public-homepage-reference.html` disagree about a pixel value,
   colour, timing, easing or breakpoint, the reference wins. Copy values; do not
   re-derive them.

2. **No raw hex, `rgb()` or `rgba()` literals in any `.ts` / `.tsx` file.**
   `customer/.eslintrc.json` fails the build on them
   (`no-restricted-syntax`). Only `src/theme/tokens.ts` and `tailwind.config.ts`
   are exempt. Colours belong in `site.css`; TypeScript reads them back through
   CSS custom properties. `hsl(...)` strings are **not** banned and are used by
   the facet generator.

3. **CSS scope class is `da`.** Every selector ported from the reference
   stylesheet is prefixed with `.da `. The public layout's outermost element
   carries `className="da"`. The only exceptions are listed in Task 2.

4. **Light-only.** No `dark:` variants, no `[data-theme="dark"]` rules, no
   `prefers-color-scheme` rules anywhere in `site.css`. Decision D-2.

5. **No Google Fonts `<link>`.** Fonts are self-hosted through `next/font`.
   Decision in spec §4.4.

6. **Every `prefers-reduced-motion: reduce` branch in the reference must be
   preserved** — both the CSS media queries and the JavaScript `reduceMotion`
   guards.

7. **Dynamic numbers show the exact count with no `+` suffix.** Static
   marketing figures keep their `+` / `$` / `B+` / `M+` affixes exactly as the
   reference has them. A real member count of 512 renders as `512`, never
   `500+`.

8. **Commit after every task.** Do not run `git commit` for anything the plan
   does not list. Never amend an existing commit.

9. **Do not touch running dev servers.** Do not kill processes, do not delete
   `.next/` or `dist/`.

10. **Backend verification:** `npm run typecheck && npm run lint && npm test`
    from `backend/`.
    **Customer verification:** `npm run typecheck && npm run lint` from
    `customer/`. The customer app has **no test runner**; pure helpers are
    verified by `npm run verify:home` (added in Task 3), following the existing
    `verify:crypto` precedent.

---

## File Structure

### Backend — new module `backend/src/modules/site/`

| File | Responsibility |
|---|---|
| `site.types.ts` | The `SiteStats` response shape |
| `site.repository.ts` | The four Prisma reads. Every read filters `deletedAt: null` and `status: ACTIVE` |
| `site.service.ts` | Assembles `SiteStats`; owns the 5-minute in-process cache |
| `site.controller.ts` | One handler |
| `site.routes.ts` | `sitePublicRouter` — no authentication, by definition |
| `site.service.test.ts` | vitest: the active-only rule, the cache, empty database |

### Backend — modified

| File | Change |
|---|---|
| `src/constant/endPoints.constant.ts` | Add `SITE: '/site'` |
| `src/routes/index.ts` | Mount `sitePublicRouter` under `PUBLIC` |

### Customer — new

| File | Responsibility |
|---|---|
| `src/components/site/site.css` | The ported reference stylesheet, `.da`-scoped |
| `src/components/site/SiteHeader.tsx` | Sticky header + mobile nav (client) |
| `src/components/site/SiteFooter.tsx` | Footer (server) |
| `src/constants/homeContent.ts` | **All** static copy and static figures |
| `src/utils/home/facets.ts` | Seeded PRNG + facet polygon geometry (pure) |
| `src/utils/home/eventTag.ts` | Spec §5 tag rules (pure) |
| `src/utils/home/eventDate.ts` | `"24"` / `"SEP 2026"` split (pure) |
| `src/utils/home/worldMap.ts` | Continent ellipses, `inContinent`, fallback hubs (pure) |
| `src/utils/home/countryPositions.ts` | ISO-2 → normalised map position (pure) |
| `src/services/SiteService.ts` | `GET /public/site/stats` |
| `src/hooks/useSiteStats.ts` | Fetch-once hook with static fallback |
| `src/components/home/primitives/ArrowIcon.tsx` | The 14×14 arrow used in every link |
| `src/components/home/primitives/Eyebrow.tsx` | `.eyebrow` label |
| `src/components/home/primitives/FacetSvg.tsx` | Generative facet `<svg>` (client) |
| `src/components/home/primitives/Reveal.tsx` | `[data-reveal]` observer wrapper (client) |
| `src/components/home/primitives/StatNumber.tsx` | Count-up number (client) |
| `src/components/home/primitives/WorldMap.tsx` | Canvas map (client) |
| `src/components/home/HomeHero.tsx` | Hero |
| `src/components/home/StatsStrip.tsx` | 4-stat strip |
| `src/components/home/UpcomingEvents.tsx` | Event rows (client, fetches) |
| `src/components/home/AboutBlock.tsx` | About |
| `src/components/home/PillarsGrid.tsx` | 6 pillars |
| `src/components/home/EmpoweringList.tsx` | 4 numbered rows |
| `src/components/home/IndustryGlance.tsx` | 4 stats + static chart |
| `src/components/home/ResourcesList.tsx` | 6 resource rows |
| `src/components/home/GlobalCommunity.tsx` | Map card + 3 community stats |
| `src/components/home/MembersMarquee.tsx` | Marquee (client, fetches) |
| `src/components/home/PartnersWall.tsx` | Partner chips |
| `src/components/home/MembershipCta.tsx` | Dark membership section |
| `src/components/home/FinalCta.tsx` | Dark final CTA |
| `scripts/verify-home-helpers.ts` | Executable checks for the pure helpers |

### Customer — modified

| File | Change |
|---|---|
| `src/app/layout.tsx` | Add Geist Mono via the `geist` package |
| `src/app/(public)/layout.tsx` | Swap `PublicHeader`/`PublicFooter` for `SiteHeader`/`SiteFooter`; add `className="da"`; import `site.css` |
| `src/app/(public)/page.tsx` | Replaced wholesale |
| `src/constants/endpoints.ts` | Add `publicSiteStats` |
| `package.json` | Add `geist` dependency and `verify:home` script |

### Customer — deleted

`PublicHeader.tsx` and `PublicFooter.tsx` are **kept on disk but unused** after
Task 5, so a rollback is a one-line change in the layout. Do not delete them.

---

## Task 1: Backend public site-stats endpoint

**Files:**
- Create: `backend/src/modules/site/site.types.ts`
- Create: `backend/src/modules/site/site.repository.ts`
- Create: `backend/src/modules/site/site.service.ts`
- Create: `backend/src/modules/site/site.controller.ts`
- Create: `backend/src/modules/site/site.routes.ts`
- Test: `backend/src/modules/site/site.service.test.ts`
- Modify: `backend/src/constant/endPoints.constant.ts`
- Modify: `backend/src/routes/index.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `GET /api/v1/public/site/stats` answering
  `{ members: number; countries: number; member_names: string[]; hub_countries: { iso_code: string; name: string; members: number }[] }`
  inside the standard response envelope (`{ data: ... }`, encrypted like every
  other endpoint). Task 6 consumes it.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/site/site.service.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const memberCount = vi.fn();
const memberFindMany = vi.fn();
const addressGroupBy = vi.fn();
const countryFindMany = vi.fn();

vi.mock('@db/prisma', () => ({
  prisma: {
    member: {
      count: (...a: unknown[]) => memberCount(...a),
      findMany: (...a: unknown[]) => memberFindMany(...a),
    },
    memberAddress: { groupBy: (...a: unknown[]) => addressGroupBy(...a) },
    country: { findMany: (...a: unknown[]) => countryFindMany(...a) },
  },
}));

const { getSiteStats, __resetSiteStatsCache } = await import('@modules/site/site.service');

beforeEach(() => {
  vi.clearAllMocks();
  __resetSiteStatsCache();
  memberCount.mockResolvedValue(0);
  memberFindMany.mockResolvedValue([]);
  addressGroupBy.mockResolvedValue([]);
  countryFindMany.mockResolvedValue([]);
});

/**
 * The homepage is the association's front door. A DRAFT company that has not
 * paid is not a member, and a member who asked to stay out of the directory is
 * not a name we publish — both rules are WHERE clauses here, not something a
 * component is trusted to filter afterwards.
 */
describe('getSiteStats', () => {
  it('counts only live ACTIVE members', async () => {
    memberCount.mockResolvedValue(512);

    const stats = await getSiteStats();

    expect(stats.members).toBe(512);
    expect(memberCount).toHaveBeenCalledWith({
      where: { deletedAt: null, status: 'ACTIVE' },
    });
  });

  it('publishes names only for members who consented to the directory', async () => {
    memberFindMany.mockResolvedValue([{ company_name: 'Acme Diamonds' }]);

    const stats = await getSiteStats();

    expect(stats.member_names).toEqual(['Acme Diamonds']);
    expect(memberFindMany).toHaveBeenCalledWith({
      where: {
        deletedAt: null,
        status: 'ACTIVE',
        directory_visible: true,
      },
      select: { company_name: true },
      orderBy: { company_name: 'asc' },
      take: 24,
    });
  });

  it('counts distinct countries and names the busiest ones', async () => {
    addressGroupBy.mockResolvedValue([
      { country_id: 1n, _count: { _all: 210 } },
      { country_id: 2n, _count: { _all: 12 } },
    ]);
    countryFindMany.mockResolvedValue([
      { id: 1n, name: 'India', iso_code: 'IN' },
      { id: 2n, name: 'Belgium', iso_code: 'BE' },
    ]);

    const stats = await getSiteStats();

    expect(stats.countries).toBe(2);
    expect(stats.hub_countries).toEqual([
      { iso_code: 'IN', name: 'India', members: 210 },
      { iso_code: 'BE', name: 'Belgium', members: 12 },
    ]);
  });

  it('answers an empty database with zeroes and empty lists, never null', async () => {
    const stats = await getSiteStats();

    expect(stats).toEqual({
      members: 0,
      countries: 0,
      member_names: [],
      hub_countries: [],
    });
  });

  /**
   * Four queries on every homepage render is four queries too many. The numbers
   * move once a day at most, so a five-minute window is invisible to a visitor
   * and removes the load entirely.
   */
  it('serves a second call from cache without re-querying', async () => {
    memberCount.mockResolvedValue(7);

    await getSiteStats();
    await getSiteStats();

    expect(memberCount).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && npx vitest run src/modules/site/site.service.test.ts
```

Expected: FAIL — `Cannot find module '@modules/site/site.service'`.

- [ ] **Step 3: Write `site.types.ts`**

```ts
/** One country the association has members in, as the homepage map plots it. */
export interface SiteHubCountry {
  /** ISO 3166-1 alpha-2. The customer app maps this to a position on its map. */
  iso_code: string;
  name: string;
  members: number;
}

/**
 * The four numbers the public homepage is allowed to state as fact.
 *
 * Everything else on that page — years of leadership, global trade value,
 * annual production, the trend chart, the partner list — is marketing copy the
 * association supplies, and it lives in the customer app's constants rather
 * than pretending to be data (spec §2, decision D-3).
 */
export interface SiteStats {
  members: number;
  countries: number;
  member_names: string[];
  hub_countries: SiteHubCountry[];
}
```

- [ ] **Step 4: Write `site.repository.ts`**

```ts
import type { Db } from '@db/prisma';

/**
 * Reads behind the public homepage.
 *
 * Every query here filters `deletedAt: null` and `status: ACTIVE`. That pairing
 * is the whole reason these live in one file: "the homepage counts paid members
 * only" is a WHERE clause in this module, not a rule each caller is trusted to
 * remember.
 */

const ACTIVE_MEMBER = { deletedAt: null, status: 'ACTIVE' } as const;

/** How many company names the marquee is given. It shows far fewer at a time. */
export const MEMBER_NAME_LIMIT = 24;

/** How many countries the map plots. Beyond a dozen the dots stop reading. */
export const HUB_COUNTRY_LIMIT = 12;

export const countActiveMembers = (db: Db) => db.member.count({ where: { ...ACTIVE_MEMBER } });

/**
 * Names for the marquee — and only from members who consented to appear.
 * `directory_visible` is the member's own choice; publishing a name against it
 * on the homepage would be the same disclosure the directory refuses to make.
 */
export const listActiveMemberNames = (db: Db) =>
  db.member.findMany({
    where: { ...ACTIVE_MEMBER, directory_visible: true },
    select: { company_name: true },
    orderBy: { company_name: 'asc' },
    take: MEMBER_NAME_LIMIT,
  });

/**
 * Members per country, busiest first.
 *
 * Grouped on the address rather than the member because the country lives on
 * the address. A member with two addresses in one country is counted twice
 * here, which affects only the ordering of the dots — never the country count,
 * which is the number of groups.
 */
export const groupMembersByCountry = (db: Db) =>
  db.memberAddress.groupBy({
    by: ['country_id'],
    where: {
      deletedAt: null,
      country_id: { not: null },
      member: { ...ACTIVE_MEMBER },
    },
    _count: { _all: true },
    orderBy: { _count: { country_id: 'desc' } },
  });

export const findCountriesByIds = (db: Db, ids: bigint[]) =>
  db.country.findMany({
    where: { id: { in: ids } },
    select: { id: true, name: true, iso_code: true },
  });
```

- [ ] **Step 5: Write `site.service.ts`**

```ts
import { prisma } from '@db/prisma';
import * as repo from '@modules/site/site.repository';
import type { SiteStats } from '@modules/site/site.types';

/**
 * The public homepage's four facts.
 *
 * Cached in process for five minutes. The homepage is the most-hit page in the
 * product and these numbers move once a day at most, so the alternative is four
 * queries per visitor for a figure that would not have changed between them.
 * The cache is deliberately per-process and not shared: a stale count on one
 * node for at most five minutes is not a correctness problem, and a shared
 * cache would be new infrastructure for a rounding-scale benefit.
 */

const TTL_MS = 5 * 60 * 1000;

let cached: { at: number; value: SiteStats } | null = null;

/** Test seam. Never called by application code. */
export const __resetSiteStatsCache = (): void => {
  cached = null;
};

const load = async (): Promise<SiteStats> => {
  const [members, names, groups] = await Promise.all([
    repo.countActiveMembers(prisma),
    repo.listActiveMemberNames(prisma),
    repo.groupMembersByCountry(prisma),
  ]);

  const ids = groups
    .map((group) => group.country_id)
    .filter((id): id is bigint => id !== null);

  const countries = ids.length ? await repo.findCountriesByIds(prisma, ids) : [];
  const byId = new Map(countries.map((country) => [country.id.toString(), country]));

  const hub_countries = groups
    .slice(0, repo.HUB_COUNTRY_LIMIT)
    .flatMap((group) => {
      const country = group.country_id ? byId.get(group.country_id.toString()) : undefined;
      if (!country) return [];

      return [{ iso_code: country.iso_code, name: country.name, members: group._count._all }];
    });

  return {
    members,
    countries: ids.length,
    member_names: names.map((row) => row.company_name),
    hub_countries,
  };
};

export const getSiteStats = async (): Promise<SiteStats> => {
  if (cached && Date.now() - cached.at < TTL_MS) return cached.value;

  const value = await load();
  cached = { at: Date.now(), value };

  return value;
};
```

- [ ] **Step 6: Write `site.controller.ts`**

```ts
import type { NextFunction, Request, RequestHandler, Response } from 'express';

import { RES_STATUS } from '@constant/message.constant';
import * as service from '@modules/site/site.service';
import { handleApiResponse } from '@utils/handleResponse';

const handler =
  (fn: (req: Request, res: Response) => Promise<void>): RequestHandler =>
  (req, res, next: NextFunction) => {
    void fn(req, res).catch(next);
  };

export const siteStats = handler(async (_req, res) => {
  handleApiResponse(res, { responseType: RES_STATUS.GET, data: await service.getSiteStats() });
});
```

- [ ] **Step 7: Write `site.routes.ts`**

```ts
import { Router } from 'express';

import { END_POINTS } from '@constant';
import * as controller from '@modules/site/site.controller';

/**
 * `/api/v1/public/site` — the numbers the marketing homepage states as fact.
 *
 * Unauthenticated by definition: this is the page a stranger lands on. Nothing
 * here is member data — a count, a country name and the company names of
 * members who chose to be listed publicly.
 */
export const sitePublicRouter = Router();

sitePublicRouter.get(`${END_POINTS.SITE}/stats`, controller.siteStats);
```

- [ ] **Step 8: Add the endpoint constant**

In `backend/src/constant/endPoints.constant.ts`, add inside the `END_POINTS`
object, immediately after the `NEWS_CATEGORIES` line:

```ts
  // The public marketing homepage's own numbers — member and country counts.
  SITE: '/site',
```

- [ ] **Step 9: Mount the router**

In `backend/src/routes/index.ts`, add the import alongside the other module
imports:

```ts
import { sitePublicRouter } from '@modules/site/site.routes';
```

and mount it next to the other public routers:

```ts
// The public homepage's member/country counts. No session, no member data.
router.use(`${END_POINTS.V1}${END_POINTS.PUBLIC}`, sitePublicRouter);
```

- [ ] **Step 10: Run the test to verify it passes**

```bash
cd backend && npx vitest run src/modules/site/site.service.test.ts
```

Expected: PASS, 5 tests.

- [ ] **Step 11: Full backend verification**

```bash
cd backend && npm run typecheck && npm run lint && npm test
```

Expected: all pass. If `groupBy` with `orderBy: { _count: { country_id: 'desc' } }`
fails to typecheck against the installed Prisma version, run `npm run prisma:generate`
first; if it still fails, drop the `orderBy` from the query and sort in
`site.service.ts` with `groups.sort((a, b) => b._count._all - a._count._all)`
before slicing, and update the third test's expectation accordingly.

- [ ] **Step 12: Commit**

```bash
cd backend && git add src/modules/site src/constant/endPoints.constant.ts src/routes/index.ts
git commit -m "feat(site): public homepage stats endpoint"
```

---

## Task 2: Geist Mono and the scoped design stylesheet

**Files:**
- Modify: `customer/package.json`
- Modify: `customer/src/app/layout.tsx`
- Create: `customer/src/components/site/site.css`

**Interfaces:**
- Consumes: nothing.
- Produces: the CSS custom properties `--da-*` and every class the reference
  uses (`.wrap`, `.section`, `.btn`, `.link-arrow`, `.eyebrow`, `.stat-number`,
  `.event-row`, …), all reachable only inside an element carrying `class="da"`.
  Also produces `--font-geist-mono`. Every later task consumes these.

- [ ] **Step 1: Add the Geist font package**

```bash
cd customer && npm install geist@^1.3.1
```

The reference loads Geist and Geist Mono from Google Fonts. Geist Sans is
already self-hosted in `src/fonts`, but Geist Mono is not, and the reference
uses it for every number on the page. The `geist` package ships both as
`next/font` modules, so this adds the mono face without a network request at
runtime and without a Google Fonts `<link>` (Global Constraint 5).

If the install cannot reach the registry, stop and report it — do not silently
fall back to a system mono. The numbers are the loudest thing on this page.

- [ ] **Step 2: Wire Geist Mono into the root layout**

In `customer/src/app/layout.tsx`, add the import next to the existing
`localFont` import:

```ts
import { GeistMono } from 'geist/font/mono';
```

Then change the `<body>` line from:

```tsx
      <body className={`${geist.variable} font-sans antialiased`}>
```

to:

```tsx
      <body className={`${geist.variable} ${GeistMono.variable} font-sans antialiased`}>
```

`GeistMono.variable` publishes `--font-geist-mono`, which `site.css` reads in
Step 3.

- [ ] **Step 3: Port the reference stylesheet**

Create `customer/src/components/site/site.css` by transforming the `<style>`
block of `docs/superpowers/specs/2026-08-31-public-homepage-reference.html`.

**The transformation, applied mechanically to every rule:**

| Reference selector | Becomes |
|---|---|
| `:root{...}` | `.da{...}` (the variables live on the scope element) |
| `body{...}` | `.da{...}` — merge into the same block, minus `margin:0` and `overflow-x:hidden` |
| `*,*::before,*::after` | `.da *,.da *::before,.da *::after` |
| `html{scroll-behavior:smooth}` | `html{scroll-behavior:smooth}` — **keep unscoped** |
| `body.nav-open{overflow:hidden}` | `body.nav-open{overflow:hidden}` — **keep unscoped** |
| `.skip-link{...}` | **omit entirely** — `src/app/globals.css` already defines it |
| `#worldmap{...}` | `.da .da-worldmap{...}` (an id would collide; see Task 4) |
| any other selector `X` | `.da X` |
| a selector list `X,Y` | `.da X,.da Y` — prefix **each** comma-separated part |
| `@media` / `@keyframes` blocks | keep the at-rule, prefix the selectors inside it |

**Rename the variables** so they cannot collide with the app's own tokens:
every `--x` defined in the reference `:root` becomes `--da-x`, and every
`var(--x)` reference becomes `var(--da-x)`. So `--bg` → `--da-bg`,
`--text-secondary` → `--da-text-secondary`, `--font-mono` → `--da-font-mono`,
and so on for all 40 of them.

**Three values change** from the reference; everything else is copied verbatim:

```css
  --da-font-sans: var(--font-geist), -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  --da-font-mono: var(--font-geist-mono), ui-monospace, 'SF Mono', Menlo, Consolas, monospace;
```

(the reference names the Google-hosted `'Geist'` / `'Geist Mono'` families; ours
come from `next/font`), and the scope block gains one property the reference did
not need:

```css
.da { display: flow-root; }
```

**Add these four rules at the end of the file.** They exist because TypeScript
may not contain colour literals (Global Constraint 2), so the facet generator
and the canvas map read their colours from CSS instead:

```css
/* The facet polygons' hairline. Set here, not as an SVG attribute, because the
   generator that draws them is TypeScript and may not name a colour. */
.da .facet-svg polygon { stroke: rgba(10, 10, 10, .05); stroke-width: .5; }
.da .final-cta .facet-svg polygon { stroke: rgba(255, 255, 255, .05); }

/* Read back by WorldMap through getComputedStyle — a canvas cannot inherit CSS. */
.da .da-worldmap {
  --da-map-land: #D4D4D4;
  --da-map-dot: #171717;
  --da-map-halo: rgba(23, 23, 23, .12);
}
```

**Verify the port covers everything.** After writing the file:

```bash
cd customer && grep -c '^\s*\.da\|^\s*@media\|^\s*@keyframes' src/components/site/site.css
```

Expected: a non-zero count. Then eyeball that these class names all appear in
the file — they are the ones later tasks depend on:

```bash
cd customer && for c in wrap section section--surface section--dark eyebrow section-head muted btn btn-primary btn-primary--inverse btn-outline link-arrow cta-group site-header header-inner logo logo-mark logo-word main-nav header-actions member-login menu-toggle mobile-nav hero hero-grid hero-content hero-visual facet-svg sheen caption stats-strip stats-grid stat-item stat-number stat-label events-list event-row event-date event-main event-meta event-loc event-desc tag tag--success tag--warning tag--neutral event-thumb about-grid about-visual about-content pillars-grid pillar-card pillar-icon empower-row empower-list empower-num empower-main glance-stats chart-card chart-head chart-note chart-svg glance-cta resource-row resource-list resource-icon resource-num resource-main resources-cta map-card map-canvas-wrap map-legend community-stats marquee marquee-track marquee-group logo-cell members-cta partners-cta partners-wall partner-chip membership-grid membership-content benefits-grid benefit-item final-cta facet-bg footer-top footer-brand footer-col footer-bottom legal; do grep -q "\.$c\b" src/components/site/site.css || echo "MISSING: .$c"; done
```

Expected: **no output**. Any `MISSING:` line means that rule was dropped in the
port — go back and add it.

- [ ] **Step 4: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

Expected: both pass. (`site.css` is not linted; the check here is that the
`layout.tsx` edit compiles and that `geist` resolves.)

- [ ] **Step 5: Commit**

```bash
cd customer && git add package.json package-lock.json src/app/layout.tsx src/components/site/site.css
git commit -m "feat(site): scoped homepage stylesheet and Geist Mono"
```

---

## Task 3: Static content, pure helpers and their verification script

**Files:**
- Create: `customer/src/constants/homeContent.ts`
- Create: `customer/src/utils/home/facets.ts`
- Create: `customer/src/utils/home/eventTag.ts`
- Create: `customer/src/utils/home/eventDate.ts`
- Create: `customer/src/utils/home/worldMap.ts`
- Create: `customer/src/utils/home/countryPositions.ts`
- Create: `customer/scripts/verify-home-helpers.ts`
- Modify: `customer/package.json`

**Interfaces:**
- Consumes: `EventListItem` from `@/services/EventService` (already exists).
- Produces, for Tasks 4–9:
  - `HOME_CONTENT` — the whole static copy tree
  - `STATIC_FIGURES` — `{ years, globalTrade, annualProduction, partnersCount, fallbackMembers, fallbackCountries }`
  - `buildFacetPolygons(opts: FacetOptions): FacetPolygon[]` where
    `FacetOptions = { seed: number; rings: number; width: number; height: number; dark?: boolean }`
    and `FacetPolygon = { points: string; fill: string }`
  - `eventTag(event: EventListItem, now?: Date): { label: string; variant: 'success' | 'warning' | 'neutral' }`
  - `splitEventDate(iso: string): { day: string; monthYear: string }`
  - `CONTINENTS`, `FALLBACK_HUBS`, `inContinent(nx: number, ny: number): boolean`
  - `COUNTRY_POSITIONS: Record<string, { x: number; y: number }>`

- [ ] **Step 1: Write `src/utils/home/facets.ts`**

This is a direct port of `buildFacets` from the reference `<script>`. The PRNG
sequence must be identical, so keep the operations in the same order.

```ts
/**
 * The low-poly diamond facets the homepage uses instead of photography.
 *
 * A straight port of the reference design's generator. The arithmetic is
 * deliberately unchanged — including the multiply-by-97-plus-13 seed mix and
 * the order the random numbers are drawn in — because the same seed has to
 * produce the same diamond it produces in the reference file. Tidying the
 * sequence would silently redraw every facet on the page.
 *
 * Colour is `hsl()` rather than hex on purpose: this file is TypeScript, where
 * hex and rgb() literals are banned (design-system.md §5).
 */

export interface FacetOptions {
  seed: number;
  rings: number;
  /** The SVG viewBox, which the geometry is expressed in. */
  width: number;
  height: number;
  /** The final-CTA background sits on near-black and inverts the tone range. */
  dark?: boolean;
}

export interface FacetPolygon {
  /** Ready for an SVG `points` attribute. */
  points: string;
  fill: string;
}

/** Lehmer / Park-Miller. Same constants as the reference. */
const seeded = (seed: number): (() => number) => {
  let s = seed % 2147483647;
  if (s <= 0) s += 2147483646;

  return () => {
    s = (s * 16807) % 2147483647;
    return (s - 1) / 2147483646;
  };
};

/** Facets per ring. Twelve is what the reference cuts. */
const N = 12;

const LIGHT_ANGLE = Math.PI * 0.28;

export function buildFacetPolygons(options: FacetOptions): FacetPolygon[] {
  const { seed, rings, width: w, height: h, dark = false } = options;

  const rand = seeded(seed * 97 + 13);
  const cx = w / 2;
  const cy = h / 2;
  const maxR = Math.min(w, h) / 2 - 2;

  const ringPts: { x: number; y: number }[][] = [];

  for (let r = 0; r < rings; r += 1) {
    const radius = maxR * ((r + 1) / rings);
    const pts: { x: number; y: number }[] = [];

    for (let i = 0; i < N; i += 1) {
      const angle = (i / N) * Math.PI * 2 + (rand() - 0.5) * 0.18;
      const rr = radius * (0.86 + rand() * 0.16);

      pts.push({
        x: cx + Math.cos(angle) * rr,
        y: cy + Math.sin(angle) * rr * (h / w > 1 ? w / h : 1),
      });
    }

    ringPts.push(pts);
  }

  const tone = (angle: number, depth: number): string => {
    let b = Math.cos(angle - LIGHT_ANGLE) * 0.5 + 0.5;
    b = b * 0.7 + depth * 0.3;

    const lo = dark ? 8 : 34;
    const hi = dark ? 46 : 98;

    return `hsl(0,0%,${(lo + b * (hi - lo)).toFixed(1)}%)`;
  };

  const out: FacetPolygon[] = [];

  const push = (points: { x: number; y: number }[], angle: number, depth: number): void => {
    out.push({
      points: points.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' '),
      fill: tone(angle, depth),
    });
  };

  // The table: triangles from the centre out to the innermost ring.
  for (let i = 0; i < N; i += 1) {
    push([{ x: cx, y: cy }, ringPts[0][i], ringPts[0][(i + 1) % N]], (i / N) * Math.PI * 2, 0.15);
  }

  // The pavilion: each ring quad split into two triangles, as the reference does.
  for (let r = 0; r < rings - 1; r += 1) {
    for (let i = 0; i < N; i += 1) {
      const p0 = ringPts[r][i];
      const p1 = ringPts[r][(i + 1) % N];
      const p2 = ringPts[r + 1][(i + 1) % N];
      const p3 = ringPts[r + 1][i];
      const ang = (i / N) * Math.PI * 2;
      const depth = (r + 1) / rings;

      push([p0, p1, p2], ang, depth);
      push([p0, p2, p3], ang, depth);
    }
  }

  return out;
}
```

- [ ] **Step 2: Write `src/utils/home/eventDate.ts`**

```ts
/**
 * The event row's date block: a big day number over a small month and year.
 *
 * `en-GB` with an explicit UTC time zone, not the visitor's locale or zone. An
 * event listed as the 24th must read as the 24th in every country the
 * association has members in — a Mumbai conference silently becoming the 23rd
 * for a reader in New York is worse than showing one fixed reference date.
 */
export interface EventDateParts {
  /** Zero-padded day of month, e.g. "08". */
  day: string;
  /** Uppercase month and year, e.g. "SEP 2026". */
  monthYear: string;
}

export function splitEventDate(iso: string): EventDateParts {
  const date = new Date(iso);

  if (Number.isNaN(date.getTime())) return { day: '--', monthYear: '' };

  const day = new Intl.DateTimeFormat('en-GB', { day: '2-digit', timeZone: 'UTC' }).format(date);
  const month = new Intl.DateTimeFormat('en-GB', { month: 'short', timeZone: 'UTC' }).format(date);
  const year = new Intl.DateTimeFormat('en-GB', { year: 'numeric', timeZone: 'UTC' }).format(date);

  return { day, monthYear: `${month} ${year}`.toUpperCase() };
}
```

- [ ] **Step 3: Write `src/utils/home/eventTag.ts`**

```ts
import type { EventListItem } from '@/services/EventService';

/**
 * The coloured pill on an event row — spec §5.
 *
 * Order matters and is not alphabetical: sold out beats closed beats nearly
 * full. A visitor reading "Limited Seats" on an event with no seats left would
 * click through to a dead end, so the most restrictive true statement wins.
 */
export type EventTagVariant = 'success' | 'warning' | 'neutral';

export interface EventTag {
  label: string;
  variant: EventTagVariant;
}

/** Below this many remaining seats the row says so. */
export const LIMITED_SEATS_THRESHOLD = 20;

export function eventTag(event: EventListItem, now: Date = new Date()): EventTag {
  if (event.seats_left !== null && event.seats_left <= 0) {
    return { label: 'Sold Out', variant: 'neutral' };
  }

  if (event.registration_closes_at && new Date(event.registration_closes_at) < now) {
    return { label: 'Registration Closed', variant: 'neutral' };
  }

  if (event.seats_left !== null && event.seats_left <= LIMITED_SEATS_THRESHOLD) {
    return { label: 'Limited Seats', variant: 'warning' };
  }

  return { label: 'Registration Open', variant: 'success' };
}
```

- [ ] **Step 4: Write `src/utils/home/worldMap.ts`**

Copy the `continents` and `hubs` arrays and the `inContinent` function verbatim
from the reference `<script>`; only the types and names are new.

```ts
/**
 * The generative world map.
 *
 * The continents are ellipses, not a real projection — this is a decorative
 * dot field, and a GeoJSON world would be two orders of magnitude more bytes
 * for a picture nobody reads coastlines off. The numbers are copied from the
 * reference design unchanged.
 */

export interface Ellipse {
  cx: number;
  cy: number;
  rx: number;
  ry: number;
  /** Degrees. */
  rot: number;
}

export interface Hub {
  /** Normalised 0–1 position within the canvas. */
  x: number;
  y: number;
  label: string;
}

export const CONTINENTS: Ellipse[] = [
  { cx: 0.14, cy: 0.34, rx: 0.075, ry: 0.11, rot: -15 },
  { cx: 0.085, cy: 0.2, rx: 0.045, ry: 0.05, rot: 0 },
  { cx: 0.175, cy: 0.44, rx: 0.025, ry: 0.045, rot: 10 },
  { cx: 0.22, cy: 0.63, rx: 0.04, ry: 0.135, rot: 8 },
  { cx: 0.47, cy: 0.21, rx: 0.042, ry: 0.06, rot: -5 },
  { cx: 0.49, cy: 0.5, rx: 0.065, ry: 0.16, rot: 0 },
  { cx: 0.66, cy: 0.27, rx: 0.15, ry: 0.135, rot: 0 },
  { cx: 0.6, cy: 0.185, rx: 0.05, ry: 0.04, rot: 0 },
  { cx: 0.755, cy: 0.4, rx: 0.075, ry: 0.095, rot: 10 },
  { cx: 0.815, cy: 0.665, rx: 0.045, ry: 0.03, rot: 0 },
];

/**
 * What the map shows before the API answers, and if it never does. These are
 * the diamond trade's actual hub cities, so the picture is honest even when it
 * is not yet ours.
 */
export const FALLBACK_HUBS: Hub[] = [
  { x: 0.16, y: 0.32, label: 'New York' },
  { x: 0.47, y: 0.23, label: 'Antwerp' },
  { x: 0.58, y: 0.38, label: 'Dubai' },
  { x: 0.665, y: 0.4, label: 'Mumbai' },
  { x: 0.755, y: 0.335, label: 'Hong Kong' },
  { x: 0.505, y: 0.62, label: 'Johannesburg' },
  { x: 0.85, y: 0.7, label: 'Sydney' },
  { x: 0.245, y: 0.66, label: 'São Paulo' },
];

export function inContinent(nx: number, ny: number): boolean {
  return CONTINENTS.some((c) => {
    const rad = (c.rot * Math.PI) / 180;
    const dx = nx - c.cx;
    const dy = ny - c.cy;
    const rxp = dx * Math.cos(-rad) - dy * Math.sin(-rad);
    const ryp = dx * Math.sin(-rad) + dy * Math.cos(-rad);

    return (rxp * rxp) / (c.rx * c.rx) + (ryp * ryp) / (c.ry * c.ry) <= 1;
  });
}
```

- [ ] **Step 5: Write `src/utils/home/countryPositions.ts`**

```ts
/**
 * Where a country's dot goes on the generative map.
 *
 * The `Countries` table has an ISO code but no coordinates, and adding a
 * lat/long column to satisfy a decorative dot field would be a schema change in
 * service of a picture. This table is the map's own business, so it lives with
 * the map: a hand-placed position per ISO-2 code, in the same normalised 0–1
 * space the continent ellipses use.
 *
 * A country that is not listed here is simply not plotted. It still counts
 * toward "Countries Represented" — the count comes from the API, not from this
 * table — so an unlisted country under-draws the map without ever
 * under-reporting the number.
 */
export const COUNTRY_POSITIONS: Record<string, { x: number; y: number }> = {
  AE: { x: 0.58, y: 0.38 },
  AU: { x: 0.85, y: 0.7 },
  BE: { x: 0.47, y: 0.23 },
  BR: { x: 0.245, y: 0.66 },
  CA: { x: 0.15, y: 0.2 },
  CH: { x: 0.475, y: 0.26 },
  CN: { x: 0.74, y: 0.3 },
  DE: { x: 0.485, y: 0.24 },
  ES: { x: 0.44, y: 0.29 },
  FR: { x: 0.46, y: 0.26 },
  GB: { x: 0.45, y: 0.21 },
  HK: { x: 0.755, y: 0.335 },
  ID: { x: 0.775, y: 0.53 },
  IL: { x: 0.55, y: 0.33 },
  IN: { x: 0.665, y: 0.4 },
  IT: { x: 0.485, y: 0.28 },
  JP: { x: 0.815, y: 0.31 },
  KE: { x: 0.545, y: 0.53 },
  KR: { x: 0.79, y: 0.3 },
  LK: { x: 0.675, y: 0.48 },
  MY: { x: 0.755, y: 0.5 },
  NL: { x: 0.47, y: 0.22 },
  NZ: { x: 0.9, y: 0.76 },
  RU: { x: 0.66, y: 0.18 },
  SA: { x: 0.565, y: 0.38 },
  SG: { x: 0.755, y: 0.52 },
  TH: { x: 0.725, y: 0.44 },
  TR: { x: 0.53, y: 0.29 },
  TW: { x: 0.775, y: 0.36 },
  US: { x: 0.16, y: 0.32 },
  VN: { x: 0.745, y: 0.44 },
  ZA: { x: 0.505, y: 0.62 },
};
```

- [ ] **Step 6: Write `src/constants/homeContent.ts`**

Every string on the homepage that is not from the API lives here. Copy the copy
verbatim from the reference; apply the link mapping from spec §4.1.

```ts
/**
 * The public homepage's static content.
 *
 * Decision D-3 (spec §2): the association supplies these figures and this copy,
 * and there is no table behind any of it. One file rather than strings scattered
 * through a dozen components, so "change 50+ to 60+" stays a one-line edit and
 * the day it becomes editable, this is the single thing that becomes a fetch.
 */

export const SITE_NAME_FALLBACK = 'Diamond Association';
export const SITE_TAGLINE = 'Global Industry Body';

/** Figures with no data source. See spec §3. */
export const STATIC_FIGURES = {
  /** Years of industry leadership. */
  years: { value: 50, suffix: '+' },
  /** Global diamond trade, USD. */
  globalTrade: { value: 80, prefix: '$', suffix: 'B+' },
  /** Annual production, carats. */
  annualProduction: { value: 130, suffix: 'M+' },
  /** Partner organisations. */
  partners: { value: 40, suffix: '+' },
  /** Shown only when `/public/site/stats` cannot be reached. */
  fallbackMembers: { value: 500, suffix: '+' },
  fallbackCountries: { value: 30, suffix: '+' },
} as const;

export const HOME_CONTENT = {
  hero: {
    eyebrow: 'Global Diamond Industry',
    heading: 'Shaping the Future of the Diamond Industry',
    lead: 'We connect, represent and empower businesses and professionals across the global diamond industry.',
    primaryCta: { label: 'Become a Member', href: '/signup' },
    secondaryCta: { label: 'Explore the Association', href: '/about' },
    caption: 'Precision-cut · craft & industry',
  },

  events: {
    eyebrow: 'Stay Involved',
    heading: 'Upcoming Events',
    viewAll: { label: 'View All Events', href: '/events' },
  },

  about: {
    eyebrow: 'About the Association',
    heading: 'Building a Stronger Diamond Industry, Together.',
    paragraphs: [
      'The Diamond Association represents businesses and professionals across mining, cutting, trading and retail — a single voice for an industry that spans continents. We exist to advocate for fair practice, connect members to opportunity, and advance the standards that keep the industry trusted.',
      "Our mission is simple: strengthen the industry's foundations so it can grow with integrity, for the people who depend on it and the generations who will inherit it.",
    ],
    cta: { label: 'Discover Our Story', href: '/about' },
  },

  pillars: {
    eyebrow: 'Our Purpose',
    heading: 'What We Stand For',
    items: [
      {
        icon: 'representation',
        title: 'Industry Representation',
        body: 'Representing the interests of businesses and professionals across the diamond industry.',
      },
      {
        icon: 'network',
        title: 'Global Member Network',
        body: 'Connecting businesses and professionals across markets.',
      },
      {
        icon: 'advocacy',
        title: 'Industry Advocacy',
        body: "Supporting the industry's interests and development.",
      },
      {
        icon: 'education',
        title: 'Education & Knowledge',
        body: 'Providing industry knowledge, training and professional development.',
      },
      {
        icon: 'standards',
        title: 'Standards & Best Practices',
        body: 'Promoting responsible and transparent industry practices.',
      },
      {
        icon: 'reach',
        title: 'Global Reach',
        body: 'Building stronger connections across the international diamond ecosystem.',
      },
    ],
  },

  empowering: {
    eyebrow: 'How We Help',
    heading: 'Empowering the Industry',
    items: [
      {
        title: 'Industry Advocacy',
        body: 'Represent and support the interests of the diamond industry.',
        href: '/about',
      },
      {
        title: 'Business & Networking',
        body: 'Create opportunities for businesses and professionals to connect and collaborate.',
        href: '/events',
      },
      {
        title: 'Education & Knowledge',
        body: 'Provide insights, research, training and professional development.',
        href: '/news',
      },
      {
        title: 'Standards & Sustainability',
        body: 'Support responsible practices, transparency and continuous improvement.',
        href: '/about',
      },
    ],
  },

  glance: {
    eyebrow: 'Industry Data',
    heading: 'The Industry at a Glance',
    chartTitle: 'Global Diamond Trade — Historical Trend',
    chartNote: 'Illustrative data · replace with verified figures at launch',
    cta: { label: 'Explore Industry Insights', href: '/news' },
  },

  resources: {
    eyebrow: 'Knowledge Center',
    heading: 'Knowledge & Resources',
    items: [
      { icon: 'document', title: 'Industry Reports', body: 'In-depth industry analysis and reports.', href: '/news' },
      { icon: 'chart', title: 'Market Research', body: 'Data and insights on global markets.', href: '/news' },
      { icon: 'shield', title: 'Guidelines & Standards', body: 'Best practices and industry standards.', href: '/about' },
      { icon: 'bookmark', title: 'Publications', body: 'Journals, reports and newsletters.', href: '/news' },
      { icon: 'sun', title: 'Circulars & Notices', body: 'Important association communications.', href: '/news' },
      { icon: 'grid', title: 'Member Resources', body: 'Tools, templates and member-only resources.', href: '/login' },
    ],
    cta: { label: 'Visit Resource Center', href: '/news' },
  },

  community: {
    eyebrow: 'Global Presence',
    heading: 'Connecting the Global Diamond Community',
    legendHub: 'Member hub city',
    legendNote: 'Dots mark the countries our members trade from',
  },

  members: {
    eyebrow: 'Our Community',
    heading: 'Our Members',
    intro: 'Businesses and professionals across the diamond ecosystem are building the future together.',
    cta: { label: 'Explore Member Directory', href: '/directory' },
  },

  partners: {
    eyebrow: 'Institutional Trust',
    heading: 'Our Partners',
    intro: 'Working with organizations across the global diamond ecosystem.',
    /** Decision D-3: static. No Partner table, no admin screen. */
    items: [
      'GLOBAL TRADE COUNCIL',
      'INTERNATIONAL GEMSTONE INSTITUTE',
      'WORLD STANDARDS ALLIANCE',
      'CHAMBER OF INTERNATIONAL COMMERCE',
      'BUREAU OF ETHICAL SOURCING',
      'FEDERATION OF TRADE ASSOCIATIONS',
      'CERTIFICATION COUNCIL INTERNATIONAL',
      'GLOBAL SUSTAINABILITY PARTNERSHIP',
      'CROSSBORDER COMMERCE ALLIANCE',
      'INSTITUTE OF INDUSTRY AFFAIRS',
    ],
    cta: { label: 'View All Partners', href: '/about' },
  },

  membership: {
    eyebrow: 'Join Us',
    heading: 'Be Part of the Diamond Community',
    body: 'Join a global network of businesses and professionals working together to strengthen the future of the diamond industry.',
    primaryCta: { label: 'Become a Member', href: '/signup' },
    secondaryCta: { label: 'Explore Membership', href: '/membership' },
    benefits: [
      { icon: 'people', label: 'Industry Networking' },
      { icon: 'building', label: 'Business Opportunities' },
      { icon: 'calendar', label: 'Exclusive Events' },
      { icon: 'chart', label: 'Industry Intelligence' },
      { icon: 'advocacy', label: 'Advocacy & Representation' },
      { icon: 'grid', label: 'Member Resources' },
    ],
  },

  finalCta: {
    eyebrow: 'Join the Association',
    heading: 'Be Part of the Future of Diamonds',
    body: 'Join a global community committed to a stronger, more connected and responsible diamond industry.',
    primaryCta: { label: 'Become a Member', href: '/signup' },
    secondaryCta: { label: 'Contact Us', href: '/contact' },
  },
} as const;

/** The public shell's primary navigation — spec §4.1. */
export const SITE_NAV = [
  { href: '/', label: 'Home' },
  { href: '/about', label: 'About' },
  { href: '/membership', label: 'Membership' },
  { href: '/#glance', label: 'Industry' },
  { href: '/events', label: 'Events' },
  { href: '/news', label: 'News & Insights' },
  { href: '/directory', label: 'Directory' },
  { href: '/contact', label: 'Contact' },
] as const;

export const SITE_FOOTER_COLUMNS = [
  {
    heading: 'Association',
    links: [
      { label: 'About Us', href: '/about' },
      { label: 'Leadership', href: '/about' },
      { label: 'Mission & Vision', href: '/about' },
      { label: 'Governance', href: '/about' },
    ],
  },
  {
    heading: 'Membership',
    links: [
      { label: 'Membership Benefits', href: '/membership' },
      { label: 'Become a Member', href: '/signup' },
      { label: 'Member Directory', href: '/directory' },
      { label: 'Member Login', href: '/login' },
    ],
  },
  {
    heading: 'Industry',
    links: [
      { label: 'Industry Insights', href: '/news' },
      { label: 'Market Data', href: '/#glance' },
      { label: 'Events', href: '/events' },
      { label: 'News', href: '/news' },
    ],
  },
  {
    heading: 'Resources',
    links: [
      { label: 'Reports', href: '/news' },
      { label: 'Publications', href: '/news' },
      { label: 'Guidelines', href: '/about' },
      { label: 'Member Resources', href: '/login' },
    ],
  },
] as const;

export const SITE_LEGAL_LINKS = [
  { label: 'Privacy Policy', href: '/about' },
  { label: 'Terms', href: '/about' },
  { label: 'Contact Us', href: '/contact' },
] as const;

export const SITE_FOOTER_BLURB =
  'Representing, connecting and advancing the global diamond industry.';
```

- [ ] **Step 7: Write `scripts/verify-home-helpers.ts`**

```ts
/**
 * Executable checks for the homepage's pure helpers.
 *
 * The customer app has no test runner, and adding one to cover four functions
 * would be a larger change than the functions. This follows `verify-crypto.ts`:
 * a script that asserts and exits non-zero, runnable in CI and by hand.
 */
import assert from 'node:assert/strict';

import { buildFacetPolygons } from '../src/utils/home/facets';
import { splitEventDate } from '../src/utils/home/eventDate';
import { eventTag } from '../src/utils/home/eventTag';
import { inContinent, FALLBACK_HUBS } from '../src/utils/home/worldMap';
import { COUNTRY_POSITIONS } from '../src/utils/home/countryPositions';
import type { EventListItem } from '../src/services/EventService';

const event = (over: Partial<EventListItem>): EventListItem =>
  ({
    id: '1',
    slug: 'e',
    title: 'E',
    banner_url: null,
    banner_alt: null,
    event_type: null,
    start_at: '2026-09-24T09:00:00.000Z',
    end_at: '2026-09-25T17:00:00.000Z',
    venue_name: null,
    city: null,
    visibility: 1,
    seats_left: null,
    registration_closes_at: null,
    tier_name: null,
    member_price: null,
    non_member_price: null,
    ...over,
  }) as EventListItem;

/* --- facets --------------------------------------------------------------- */

const hero = buildFacetPolygons({ seed: 8, rings: 5, width: 440, height: 366 });

// 12 table triangles + 2 per quad on each of (rings - 1) rings.
assert.equal(hero.length, 12 + 12 * 2 * 4, 'hero facet count');
assert.equal(
  hero.length,
  buildFacetPolygons({ seed: 8, rings: 5, width: 440, height: 366 }).length,
  'facets are deterministic in length',
);
assert.deepEqual(
  hero,
  buildFacetPolygons({ seed: 8, rings: 5, width: 440, height: 366 }),
  'the same seed draws the same diamond',
);
assert.notDeepEqual(
  hero[0],
  buildFacetPolygons({ seed: 9, rings: 5, width: 440, height: 366 })[0],
  'a different seed draws a different diamond',
);
assert.ok(
  hero.every((p) => p.fill.startsWith('hsl(') && p.points.split(' ').length === 3),
  'every facet is an hsl triangle',
);
assert.ok(
  buildFacetPolygons({ seed: 21, rings: 6, width: 1440, height: 500, dark: true }).every((p) => {
    const lightness = Number(p.fill.replace('hsl(0,0%,', '').replace('%)', ''));
    return lightness >= 8 && lightness <= 46;
  }),
  'the dark variant stays inside its tone range',
);

/* --- event date ----------------------------------------------------------- */

assert.deepEqual(splitEventDate('2026-09-24T09:00:00.000Z'), {
  day: '24',
  monthYear: 'SEP 2026',
});
assert.deepEqual(splitEventDate('2026-12-03T00:00:00.000Z'), {
  day: '03',
  monthYear: 'DEC 2026',
});
assert.deepEqual(splitEventDate('not a date'), { day: '--', monthYear: '' });

/* --- event tag ------------------------------------------------------------ */

const now = new Date('2026-09-01T00:00:00.000Z');

assert.deepEqual(eventTag(event({}), now), {
  label: 'Registration Open',
  variant: 'success',
});
assert.deepEqual(eventTag(event({ seats_left: 0 }), now), {
  label: 'Sold Out',
  variant: 'neutral',
});
assert.deepEqual(eventTag(event({ seats_left: 5 }), now), {
  label: 'Limited Seats',
  variant: 'warning',
});
assert.deepEqual(
  eventTag(event({ registration_closes_at: '2026-08-01T00:00:00.000Z' }), now),
  { label: 'Registration Closed', variant: 'neutral' },
);
// Sold out beats merely closed.
assert.deepEqual(
  eventTag(event({ seats_left: 0, registration_closes_at: '2026-08-01T00:00:00.000Z' }), now),
  { label: 'Sold Out', variant: 'neutral' },
);

/* --- map ------------------------------------------------------------------ */

assert.equal(inContinent(0.66, 0.27), true, 'the Asia ellipse contains its own centre');
assert.equal(inContinent(0.02, 0.98), false, 'the far corner is ocean');
assert.equal(FALLBACK_HUBS.length, 8);
assert.ok(
  FALLBACK_HUBS.every((h) => h.x > 0 && h.x < 1 && h.y > 0 && h.y < 1),
  'fallback hubs are normalised',
);
assert.ok(
  Object.values(COUNTRY_POSITIONS).every((p) => p.x > 0 && p.x < 1 && p.y > 0 && p.y < 1),
  'country positions are normalised',
);
assert.ok(COUNTRY_POSITIONS.IN && COUNTRY_POSITIONS.US && COUNTRY_POSITIONS.BE);

console.log('home helpers OK');
```

- [ ] **Step 8: Add the npm script**

In `customer/package.json`, add to `scripts`, immediately after `verify:crypto`:

```json
    "verify:home": "tsx scripts/verify-home-helpers.ts"
```

- [ ] **Step 9: Run the verification**

```bash
cd customer && npm run verify:home
```

Expected: `home helpers OK` and exit code 0. If the facet-count assertion fails,
the port in Step 1 changed the loop bounds — re-read the reference `buildFacets`.

- [ ] **Step 10: Verify types and lint**

```bash
cd customer && npm run typecheck && npm run lint
```

Expected: both pass. In particular there must be **no** `no-restricted-syntax`
error — if one appears, a hex or `rgb()` literal slipped into a `.ts` file.

- [ ] **Step 11: Commit**

```bash
cd customer && git add src/constants/homeContent.ts src/utils/home scripts/verify-home-helpers.ts package.json
git commit -m "feat(home): static content and pure homepage helpers"
```

---

## Task 4: Shared homepage primitives

**Files:**
- Create: `customer/src/components/home/primitives/ArrowIcon.tsx`
- Create: `customer/src/components/home/primitives/Eyebrow.tsx`
- Create: `customer/src/components/home/primitives/FacetSvg.tsx`
- Create: `customer/src/components/home/primitives/Reveal.tsx`
- Create: `customer/src/components/home/primitives/StatNumber.tsx`
- Create: `customer/src/components/home/primitives/WorldMap.tsx`
- Create: `customer/src/components/home/primitives/index.ts`

**Interfaces:**
- Consumes: `buildFacetPolygons`, `CONTINENTS`, `inContinent`, `FALLBACK_HUBS`,
  `Hub` from Task 3.
- Produces, for Tasks 5–9:
  - `<ArrowIcon />` — no props
  - `<Eyebrow>{text}</Eyebrow>`
  - `<FacetSvg seed rings viewWidth viewHeight dark? className? id? />`
  - `<Reveal as? className?>{children}</Reveal>`
  - `<StatNumber value prefix? suffix? />`
  - `<WorldMap hubs />` where `hubs: Hub[]`

- [ ] **Step 1: Write `ArrowIcon.tsx`**

```tsx
/** The 14×14 chevron every link and button on the homepage ends with. */
export default function ArrowIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden>
      <path
        d="M3 8h10M9 4l4 4-4 4"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
```

- [ ] **Step 2: Write `Eyebrow.tsx`**

```tsx
import type { ReactNode } from 'react';

/** The small tracked label above every section heading. Rule drawn by CSS. */
export default function Eyebrow({ children }: { children: ReactNode }) {
  return <span className="eyebrow">{children}</span>;
}
```

- [ ] **Step 3: Write `FacetSvg.tsx`**

```tsx
'use client';

import { useMemo } from 'react';

import { buildFacetPolygons } from '@/utils/home/facets';

/**
 * A generative low-poly diamond, standing in for photography.
 *
 * Rendered in a `useMemo` rather than an effect: the geometry is a pure
 * function of the props, so React can produce the polygons during render and
 * the markup arrives complete. The generator is seeded, so the server and the
 * client draw the identical diamond and hydration has nothing to reconcile —
 * which an effect-based port would have broken by drawing nothing on the server.
 *
 * The polygons carry no `stroke` attribute. Their hairline is set in `site.css`
 * because TypeScript in this app may not contain a colour literal.
 */
export interface FacetSvgProps {
  seed: number;
  rings: number;
  viewWidth: number;
  viewHeight: number;
  /** Inverts the tone range for the near-black final CTA. */
  dark?: boolean;
  className?: string;
  preserveAspectRatio?: string;
}

export default function FacetSvg({
  seed,
  rings,
  viewWidth,
  viewHeight,
  dark = false,
  className = 'facet-svg',
  preserveAspectRatio,
}: FacetSvgProps) {
  const polygons = useMemo(
    () => buildFacetPolygons({ seed, rings, width: viewWidth, height: viewHeight, dark }),
    [seed, rings, viewWidth, viewHeight, dark],
  );

  return (
    <svg
      className={className}
      viewBox={`0 0 ${viewWidth} ${viewHeight}`}
      preserveAspectRatio={preserveAspectRatio}
      aria-hidden
    >
      {polygons.map((polygon, index) => (
        <polygon key={index} points={polygon.points} fill={polygon.fill} />
      ))}
    </svg>
  );
}
```

- [ ] **Step 4: Write `Reveal.tsx`**

```tsx
'use client';

import { useEffect, useRef, useState, type ElementType, type ReactNode } from 'react';

/**
 * The fade-and-rise every stat block enters with.
 *
 * Observed once and then unobserved, exactly as the reference does — a section
 * that re-animates every time it scrolls back into view reads as a glitch.
 *
 * The `is-visible` class is added immediately, without an observer, when the
 * visitor has asked for reduced motion or the browser has no
 * IntersectionObserver. Content that only appears once an animation runs is
 * content that never appears for those visitors.
 */
export default function Reveal({
  as: Tag = 'div',
  className,
  children,
}: {
  as?: ElementType;
  className?: string;
  children: ReactNode;
}) {
  const ref = useRef<HTMLElement | null>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;

    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (reduceMotion || !('IntersectionObserver' in window)) {
      setVisible(true);
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          setVisible(true);
          observer.unobserve(entry.target);
        });
      },
      { threshold: 0.3 },
    );

    observer.observe(node);

    return () => observer.disconnect();
  }, []);

  return (
    <Tag
      ref={ref}
      data-reveal=""
      className={[className, visible ? 'is-visible' : ''].filter(Boolean).join(' ')}
    >
      {children}
    </Tag>
  );
}
```

- [ ] **Step 5: Write `StatNumber.tsx`**

```tsx
'use client';

import { useEffect, useRef, useState } from 'react';

/**
 * A statistic that counts up once, when it is half on screen.
 *
 * 1400ms with a cubic ease-out, at 50% visibility, observed once — the
 * reference's timings, unchanged.
 *
 * The final value is what renders on the server and what a reduced-motion
 * visitor sees immediately. The count starts from zero only after the observer
 * fires, so a visitor who never scrolls here, or whose JavaScript never runs,
 * still reads the number rather than a zero.
 */
export interface StatNumberProps {
  value: number;
  prefix?: string;
  suffix?: string;
}

const DURATION_MS = 1400;

export default function StatNumber({ value, prefix = '', suffix = '' }: StatNumberProps) {
  const ref = useRef<HTMLDivElement | null>(null);
  const [shown, setShown] = useState(value);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;

    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (reduceMotion || !('IntersectionObserver' in window)) {
      setShown(value);
      return;
    }

    let frame = 0;
    let start: number | null = null;

    const step = (timestamp: number) => {
      start ??= timestamp;

      const p = Math.min((timestamp - start) / DURATION_MS, 1);
      const eased = 1 - Math.pow(1 - p, 3);

      setShown(Math.round(value * eased));

      if (p < 1) frame = requestAnimationFrame(step);
    };

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;

          observer.unobserve(entry.target);
          setShown(0);
          frame = requestAnimationFrame(step);
        });
      },
      { threshold: 0.5 },
    );

    observer.observe(node);

    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    };
  }, [value]);

  return (
    <div ref={ref} className="stat-number">
      {prefix}
      {shown}
      {suffix}
    </div>
  );
}
```

- [ ] **Step 6: Write `WorldMap.tsx`**

```tsx
'use client';

import { useCallback, useEffect, useRef } from 'react';

import { inContinent, type Hub } from '@/utils/home/worldMap';

/**
 * The generative dot map.
 *
 * Canvas rather than SVG: this is ~2,500 dots redrawn on resize, which is a
 * fill loop on a canvas and 2,500 DOM nodes in SVG.
 *
 * Its three colours are read back off its own element with `getComputedStyle`.
 * A canvas cannot inherit CSS, and this app forbids colour literals in
 * TypeScript — so `site.css` sets `--da-map-*` on this element and the draw
 * loop asks for them. If a value comes back empty the draw is skipped rather
 * than guessed.
 */
const COLUMNS = 90;
const RESIZE_DEBOUNCE_MS = 150;

export default function WorldMap({ hubs }: { hubs: Hub[] }) {
  const ref = useRef<HTMLCanvasElement | null>(null);
  const hubsRef = useRef(hubs);
  hubsRef.current = hubs;

  const draw = useCallback(() => {
    const canvas = ref.current;
    if (!canvas) return;

    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (!w || !h) return;

    const styles = getComputedStyle(canvas);
    const land = styles.getPropertyValue('--da-map-land').trim();
    const dot = styles.getPropertyValue('--da-map-dot').trim();
    const halo = styles.getPropertyValue('--da-map-halo').trim();
    if (!land || !dot) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);

    const rows = Math.round(COLUMNS * (h / w));

    ctx.fillStyle = land;
    for (let gy = 0; gy < rows; gy += 1) {
      for (let gx = 0; gx < COLUMNS; gx += 1) {
        const nx = (gx + 0.5) / COLUMNS;
        const ny = (gy + 0.5) / rows;

        if (!inContinent(nx, ny)) continue;

        ctx.beginPath();
        ctx.arc(nx * w, ny * h, 1.15, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    hubsRef.current.forEach((hub) => {
      const hx = hub.x * w;
      const hy = hub.y * h;

      if (!reduceMotion && halo) {
        ctx.beginPath();
        ctx.arc(hx, hy, 8, 0, Math.PI * 2);
        ctx.fillStyle = halo;
        ctx.fill();
      }

      ctx.beginPath();
      ctx.arc(hx, hy, 3, 0, Math.PI * 2);
      ctx.fillStyle = dot;
      ctx.fill();
    });
  }, []);

  useEffect(() => {
    draw();

    let timer: ReturnType<typeof setTimeout>;
    const onResize = () => {
      clearTimeout(timer);
      timer = setTimeout(draw, RESIZE_DEBOUNCE_MS);
    };

    window.addEventListener('resize', onResize);

    // A canvas laid out while off-screen can measure zero; redraw on entry.
    const observer =
      'IntersectionObserver' in window
        ? new IntersectionObserver(
            (entries) => entries.forEach((entry) => entry.isIntersecting && draw()),
            { threshold: 0.1 },
          )
        : null;

    if (observer && ref.current) observer.observe(ref.current);

    return () => {
      window.removeEventListener('resize', onResize);
      clearTimeout(timer);
      observer?.disconnect();
    };
  }, [draw]);

  // Redraw when the hub list arrives from the API.
  useEffect(() => {
    draw();
  }, [hubs, draw]);

  return (
    <canvas
      ref={ref}
      className="da-worldmap"
      role="img"
      aria-label="World map showing the countries the association's members trade from"
    />
  );
}
```

- [ ] **Step 7: Write `index.ts`**

```ts
export { default as ArrowIcon } from './ArrowIcon';
export { default as Eyebrow } from './Eyebrow';
export { default as FacetSvg } from './FacetSvg';
export { default as Reveal } from './Reveal';
export { default as StatNumber } from './StatNumber';
export { default as WorldMap } from './WorldMap';
```

- [ ] **Step 8: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

Expected: both pass.

- [ ] **Step 9: Commit**

```bash
cd customer && git add src/components/home/primitives
git commit -m "feat(home): shared homepage primitives"
```

---

## Task 5: Public shell — SiteHeader and SiteFooter

**Files:**
- Create: `customer/src/components/site/SiteHeader.tsx`
- Create: `customer/src/components/site/SiteFooter.tsx`
- Modify: `customer/src/app/(public)/layout.tsx`

**Interfaces:**
- Consumes: `SITE_NAV`, `SITE_FOOTER_COLUMNS`, `SITE_LEGAL_LINKS`,
  `SITE_FOOTER_BLURB`, `SITE_NAME_FALLBACK`, `SITE_TAGLINE` from Task 3;
  `site.css` from Task 2.
- Produces: the `.da` scope element that every homepage section renders inside.

- [ ] **Step 1: Write `SiteHeader.tsx`**

```tsx
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';

import { SITE_NAME_FALLBACK, SITE_NAV, SITE_TAGLINE } from '@/constants/homeContent';

/**
 * The public site's header.
 *
 * The mobile panel locks body scroll while it is open and releases it on
 * unmount as well as on close — a route change that unmounted this component
 * mid-open would otherwise leave the whole site unscrollable.
 */

function LogoMark() {
  return (
    <svg className="logo-mark" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M4 9L12 2L20 9L12 22L4 9Z"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinejoin="round"
      />
      <path
        d="M4 9H20M8.5 9L12 2L15.5 9M8.5 9L12 22M15.5 9L12 22"
        stroke="currentColor"
        strokeWidth="1"
        opacity=".55"
      />
    </svg>
  );
}

export default function SiteHeader() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    document.body.classList.toggle('nav-open', open);

    return () => document.body.classList.remove('nav-open');
  }, [open]);

  // A tap that navigates must also close the panel it navigated from.
  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  const isCurrent = (href: string) =>
    href === '/' ? pathname === '/' : pathname.startsWith(href.split('#')[0]);

  return (
    <header className="site-header">
      <div className="header-inner">
        <Link className="logo" href="/" aria-label={`${SITE_NAME_FALLBACK} home`}>
          <LogoMark />
          <span className="logo-word">
            {SITE_NAME_FALLBACK.toUpperCase()}
            <small>{SITE_TAGLINE}</small>
          </span>
        </Link>

        <nav className="main-nav" aria-label="Primary">
          <ul>
            {SITE_NAV.map((item) => (
              <li key={item.href}>
                <Link href={item.href} aria-current={isCurrent(item.href) ? 'page' : undefined}>
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>

        <div className="header-actions">
          <Link className="member-login" href="/login">
            Member Login
          </Link>
          <Link className="btn btn-primary" href="/signup">
            Become a Member
          </Link>
          <button
            type="button"
            className="menu-toggle"
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            aria-controls="mobileNav"
            onClick={() => setOpen((value) => !value)}
          >
            <span />
            <span />
            <span />
          </button>
        </div>
      </div>

      <nav
        className={`mobile-nav${open ? ' is-open' : ''}`}
        id="mobileNav"
        aria-label="Mobile"
      >
        <ul>
          {SITE_NAV.map((item) => (
            <li key={item.href}>
              <Link href={item.href} onClick={() => setOpen(false)}>
                {item.label}
              </Link>
            </li>
          ))}
        </ul>
        <div className="cta-group">
          <Link className="btn btn-primary" href="/signup" onClick={() => setOpen(false)}>
            Become a Member
          </Link>
          <Link className="member-login" href="/login" onClick={() => setOpen(false)}>
            Member Login
          </Link>
        </div>
      </nav>
    </header>
  );
}
```

- [ ] **Step 2: Write `SiteFooter.tsx`**

```tsx
import Link from 'next/link';

import {
  SITE_FOOTER_BLURB,
  SITE_FOOTER_COLUMNS,
  SITE_LEGAL_LINKS,
  SITE_NAME_FALLBACK,
} from '@/constants/homeContent';

/** The public site's footer. No state, no session — a server component. */
export default function SiteFooter() {
  const year = new Date().getFullYear();

  return (
    <footer>
      <div className="wrap footer-top">
        <div className="footer-brand">
          <Link className="logo" href="/" aria-label={`${SITE_NAME_FALLBACK} home`}>
            <svg className="logo-mark" viewBox="0 0 24 24" fill="none" aria-hidden>
              <path
                d="M4 9L12 2L20 9L12 22L4 9Z"
                stroke="currentColor"
                strokeWidth="1.4"
                strokeLinejoin="round"
              />
            </svg>
            <span className="logo-word">{SITE_NAME_FALLBACK.toUpperCase()}</span>
          </Link>
          <p>{SITE_FOOTER_BLURB}</p>
        </div>

        {SITE_FOOTER_COLUMNS.map((column) => (
          <div className="footer-col" key={column.heading}>
            <h4>{column.heading}</h4>
            <ul>
              {column.links.map((link) => (
                <li key={`${column.heading}-${link.label}`}>
                  <Link href={link.href}>{link.label}</Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      <div className="wrap footer-bottom">
        <span>© {year} {SITE_NAME_FALLBACK}</span>
        <span className="legal">
          {SITE_LEGAL_LINKS.map((link) => (
            <Link key={link.label} href={link.href}>
              {link.label}
            </Link>
          ))}
        </span>
      </div>
    </footer>
  );
}
```

- [ ] **Step 3: Rewrite the public layout**

Replace the whole of `customer/src/app/(public)/layout.tsx` with:

```tsx
import type { ReactNode } from 'react';

import SiteFooter from '@/components/site/SiteFooter';
import SiteHeader from '@/components/site/SiteHeader';

import '@/components/site/site.css';

/**
 * Public shell: the association's marketing header and footer.
 *
 * `da` is the scope every rule in `site.css` is prefixed with. Without it that
 * stylesheet's resets — `a { color: inherit }`, `ul { list-style: none }` —
 * would reach the member portal and the sign-in screen, which are built on
 * Tailwind's preflight instead.
 *
 * The shell is deliberately light-only (decision D-2): it does not read the
 * theme, and the toggle still governs the member app.
 *
 * `PublicHeader`/`PublicFooter` are left in the tree unused, so reverting this
 * is a two-line change here rather than a restore.
 */
export default function PublicLayout({ children }: { children: ReactNode }) {
  return (
    <div className="da flex min-h-screen flex-col">
      <SiteHeader />
      <main id="main" className="flex-1">
        {children}
      </main>
      <SiteFooter />
    </div>
  );
}
```

- [ ] **Step 4: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

Expected: both pass.

- [ ] **Step 5: Verify visually**

Start the app if it is not already running (**do not restart one that is**):

```bash
cd customer && npm run dev
```

Open `http://localhost:3000/about` — a page this task did not otherwise touch —
and confirm:
- the new sticky header renders, translucent, 76px tall
- below 1100px the nav collapses to the hamburger, and tapping it opens a
  full-screen panel that locks page scroll
- tapping a link in the panel navigates **and** closes it
- the new 5-column footer renders and collapses to one column on a phone
- the `/about` page body is unchanged

- [ ] **Step 6: Commit**

```bash
cd customer && git add src/components/site "src/app/(public)/layout.tsx"
git commit -m "feat(site): new public header and footer shell"
```

---

## Task 6: Site stats service and hook

**Files:**
- Modify: `customer/src/constants/endpoints.ts`
- Create: `customer/src/services/SiteService.ts`
- Create: `customer/src/hooks/useSiteStats.ts`

**Interfaces:**
- Consumes: Task 1's endpoint; `STATIC_FIGURES` and `COUNTRY_POSITIONS` from Task 3.
- Produces, for Tasks 8 and 9:
  - `SiteStats` — `{ members, countries, member_names, hub_countries }`
  - `useSiteStats(): { stats: SiteStats | null; loading: boolean; failed: boolean }`
  - `hubsFromStats(stats: SiteStats | null): Hub[]`
  - `memberCount(stats)` / `countryCount(stats)` → `{ value: number; suffix: string }`

- [ ] **Step 1: Add the endpoint**

In `customer/src/constants/endpoints.ts`, add after the `publicMembership` entry:

```ts
  /* --- public homepage figures -------------------------------------------- */
  /** Member and country counts, member names, and the countries the map plots. */
  publicSiteStats: '/public/site/stats',
```

- [ ] **Step 2: Write `SiteService.ts`**

```ts
'use client';

import { ENDPOINTS } from '@/constants/endpoints';

import ApiService from './ApiService';

/**
 * The public homepage's own numbers. Mirrors `backend/src/modules/site`.
 *
 * `skipAuth` because this is the page a stranger lands on: sending a stale
 * bearer token here would put a signed-out visitor through the refresh-and-
 * redirect path for a marketing statistic.
 */

export interface SiteHubCountry {
  /** ISO 3166-1 alpha-2, matched against `COUNTRY_POSITIONS`. */
  iso_code: string;
  name: string;
  members: number;
}

export interface SiteStats {
  members: number;
  countries: number;
  member_names: string[];
  hub_countries: SiteHubCountry[];
}

export const SiteService = {
  stats: () => ApiService.get<SiteStats>(ENDPOINTS.publicSiteStats, { skipAuth: true }),
};

export default SiteService;
```

- [ ] **Step 3: Write `useSiteStats.ts`**

```ts
'use client';

import { useEffect, useState } from 'react';

import { STATIC_FIGURES } from '@/constants/homeContent';
import SiteService, { type SiteStats } from '@/services/SiteService';
import { COUNTRY_POSITIONS } from '@/utils/home/countryPositions';
import { FALLBACK_HUBS, type Hub } from '@/utils/home/worldMap';

/**
 * The homepage's four live figures, fetched once.
 *
 * Failure is silent and falls back to the association's own published figures.
 * A red error panel where "500+ Members" should be is the loudest thing on a
 * marketing page, and the visitor can do nothing about it.
 */
export function useSiteStats() {
  const [stats, setStats] = useState<SiteStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;

    SiteService.stats()
      .then((response) => {
        if (!live) return;
        setStats(response.data);
      })
      .catch(() => {
        if (!live) return;
        setFailed(true);
      })
      .finally(() => {
        if (live) setLoading(false);
      });

    return () => {
      live = false;
    };
  }, []);

  return { stats, loading, failed };
}

/**
 * Global Constraint 7: a real count is stated exactly. The `+` belongs to the
 * association's rounded marketing figure and would be a false precision claim
 * on top of a real one.
 */
export function memberCount(stats: SiteStats | null): { value: number; suffix: string } {
  if (!stats) return { value: STATIC_FIGURES.fallbackMembers.value, suffix: STATIC_FIGURES.fallbackMembers.suffix };

  return { value: stats.members, suffix: '' };
}

export function countryCount(stats: SiteStats | null): { value: number; suffix: string } {
  if (!stats) return { value: STATIC_FIGURES.fallbackCountries.value, suffix: STATIC_FIGURES.fallbackCountries.suffix };

  return { value: stats.countries, suffix: '' };
}

/**
 * The dots. A country we hold no position for is dropped rather than guessed —
 * it still counts toward "Countries Represented", which comes from the API.
 */
export function hubsFromStats(stats: SiteStats | null): Hub[] {
  if (!stats) return FALLBACK_HUBS;

  const plotted = stats.hub_countries.flatMap((country) => {
    const position = COUNTRY_POSITIONS[country.iso_code];
    if (!position) return [];

    return [{ x: position.x, y: position.y, label: country.name }];
  });

  return plotted.length ? plotted : FALLBACK_HUBS;
}
```

- [ ] **Step 4: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

Expected: both pass.

- [ ] **Step 5: Verify the endpoint answers**

With the backend running:

```bash
curl -s http://localhost:8000/api/v1/public/site/stats | head -c 400
```

Expected: an HTTP 200 with an envelope containing a `data` field. The body is
encrypted in non-local environments — a 200 with a `data` key is the assertion
here, not the plaintext. A 404 means Task 1 Step 9 did not mount the router.
Adjust the port to whatever `backend/.env` sets if 8000 is wrong.

- [ ] **Step 6: Commit**

```bash
cd customer && git add src/constants/endpoints.ts src/services/SiteService.ts src/hooks/useSiteStats.ts
git commit -m "feat(home): site stats service and hook"
```

---

## Task 7: The static homepage sections

**Files:**
- Create: `customer/src/components/home/HomeHero.tsx`
- Create: `customer/src/components/home/AboutBlock.tsx`
- Create: `customer/src/components/home/PillarsGrid.tsx`
- Create: `customer/src/components/home/EmpoweringList.tsx`
- Create: `customer/src/components/home/ResourcesList.tsx`
- Create: `customer/src/components/home/PartnersWall.tsx`
- Create: `customer/src/components/home/MembershipCta.tsx`
- Create: `customer/src/components/home/FinalCta.tsx`
- Create: `customer/src/components/home/icons.tsx`

**Interfaces:**
- Consumes: `HOME_CONTENT` (Task 3), primitives (Task 4).
- Produces: eight default-exported section components, all server components
  except where a primitive makes them client, each rendering exactly one
  `<section>`. Task 9 composes them.

- [ ] **Step 1: Write `icons.tsx`**

Copy the `<svg>` bodies verbatim from the reference — the six `.pillar-icon`
paths, the six `.resource-icon` paths and the six `.benefit-item` paths. Convert
`stroke-width` to `strokeWidth`, `stroke-linecap` to `strokeLinecap` and
`stroke-linejoin` to `strokeLinejoin`; leave every coordinate untouched.

```tsx
import type { ReactNode } from 'react';

/**
 * The homepage's line icons, lifted from the reference design.
 *
 * Kept as one map rather than one component per icon: they are 24×24 and 32×32
 * decorations picked by a string in `homeContent.ts`, and twelve one-line files
 * would be twelve files to open to find a path.
 */

const S = { stroke: 'currentColor', fill: 'none' } as const;

/** 32×32, used by the "What We Stand For" cards. */
export const PILLAR_ICONS: Record<string, ReactNode> = {
  representation: (
    <>
      <path d="M16 4L27 11V21L16 28L5 21V11L16 4Z" {...S} strokeWidth="1.3" />
      <path d="M16 4V28M5 11L27 21M27 11L5 21" {...S} strokeWidth="1" opacity=".5" />
    </>
  ),
  network: (
    <>
      <circle cx="9" cy="10" r="3.4" {...S} strokeWidth="1.3" />
      <circle cx="23" cy="10" r="3.4" {...S} strokeWidth="1.3" />
      <circle cx="16" cy="23" r="3.4" {...S} strokeWidth="1.3" />
      <path d="M11.6 12L14 20M20.4 12L18 20M12 9H20" {...S} strokeWidth="1" />
    </>
  ),
  advocacy: (
    <>
      <path d="M6 24V9L16 4L26 9V24" {...S} strokeWidth="1.3" />
      <path d="M6 24H26M11 24V16H21V24" {...S} strokeWidth="1.3" />
    </>
  ),
  education: (
    <>
      <path d="M5 9L16 5L27 9L16 13L5 9Z" {...S} strokeWidth="1.3" />
      <path d="M10 11.5V19C10 19 12.5 22 16 22C19.5 22 22 19 22 19V11.5" {...S} strokeWidth="1.3" />
      <path d="M27 9V16" {...S} strokeWidth="1.3" />
    </>
  ),
  standards: (
    <>
      <path d="M16 4L26 8V15C26 21.5 21.8 26.4 16 28C10.2 26.4 6 21.5 6 15V8L16 4Z" {...S} strokeWidth="1.3" />
      <path d="M11.5 16L14.5 19L20.5 12.5" {...S} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
    </>
  ),
  reach: (
    <>
      <circle cx="16" cy="16" r="11" {...S} strokeWidth="1.3" />
      <path d="M5 16H27M16 5C19.5 8.5 21 12 21 16C21 20 19.5 23.5 16 27C12.5 23.5 11 20 11 16C11 12 12.5 8.5 16 5Z" {...S} strokeWidth="1" />
    </>
  ),
};

/** 24×24, used by the resources list and the membership benefits grid. */
export const LINE_ICONS: Record<string, ReactNode> = {
  document: (
    <>
      <path d="M5 4h9l5 5v11H5V4Z" {...S} strokeWidth="1.3" />
      <path d="M14 4v5h5" {...S} strokeWidth="1.3" />
    </>
  ),
  chart: <path d="M4 19V9l6-4 6 4v10M4 19h16M9 19v-6h4v6" {...S} strokeWidth="1.3" />,
  shield: (
    <>
      <path d="M12 3L20 7L12 11L4 7L12 3Z" {...S} strokeWidth="1.3" />
      <path d="M6 10.5V16C6 16 8.5 19 12 19C15.5 19 18 16 18 16V10.5" {...S} strokeWidth="1.3" />
    </>
  ),
  bookmark: <path d="M5 3h14v18l-7-4-7 4V3Z" {...S} strokeWidth="1.3" />,
  sun: (
    <path
      d="M12 2v4M12 18v4M4.9 4.9l2.8 2.8M16.3 16.3l2.8 2.8M2 12h4M18 12h4M4.9 19.1l2.8-2.8M16.3 7.7l2.8-2.8"
      {...S}
      strokeWidth="1.3"
      strokeLinecap="round"
    />
  ),
  grid: (
    <>
      <rect x="4" y="4" width="7" height="7" {...S} strokeWidth="1.3" />
      <rect x="13" y="4" width="7" height="7" {...S} strokeWidth="1.3" />
      <rect x="4" y="13" width="7" height="7" {...S} strokeWidth="1.3" />
      <rect x="13" y="13" width="7" height="7" {...S} strokeWidth="1.3" />
    </>
  ),
  people: (
    <>
      <circle cx="8" cy="9" r="3" {...S} strokeWidth="1.3" />
      <circle cx="17" cy="9" r="3" {...S} strokeWidth="1.3" />
      <path d="M2 20c0-3 2.5-5 6-5s6 2 6 5M13 15.2c3.2.2 5 2 5 4.8" {...S} strokeWidth="1.3" />
    </>
  ),
  building: (
    <>
      <path d="M4 20V10l8-6 8 6v10M4 20h16" {...S} strokeWidth="1.3" />
      <path d="M9 20v-6h6v6" {...S} strokeWidth="1.3" />
    </>
  ),
  calendar: (
    <>
      <rect x="4" y="5" width="16" height="15" rx="1" {...S} strokeWidth="1.3" />
      <path d="M4 9.5h16M8 3v4M16 3v4" {...S} strokeWidth="1.3" />
    </>
  ),
  advocacy: <path d="M4 19V9l6-4 6 4v10M4 19h16" {...S} strokeWidth="1.3" />,
};
```

- [ ] **Step 2: Write `HomeHero.tsx`**

```tsx
import Link from 'next/link';

import { HOME_CONTENT } from '@/constants/homeContent';

import { ArrowIcon, Eyebrow, FacetSvg } from './primitives';

const { hero } = HOME_CONTENT;

/** The reference's hero seed and ring count. Changing either redraws the stone. */
const HERO_FACET = { seed: 8, rings: 5, width: 440, height: 366 };

export default function HomeHero() {
  return (
    <section className="hero" id="top">
      <div className="wrap hero-grid">
        <div className="hero-content">
          <Eyebrow>{hero.eyebrow}</Eyebrow>
          <h1>{hero.heading}</h1>
          <p className="lead">{hero.lead}</p>
          <div className="cta-group">
            <Link className="btn btn-primary" href={hero.primaryCta.href}>
              {hero.primaryCta.label} <ArrowIcon />
            </Link>
            <Link className="link-arrow" href={hero.secondaryCta.href}>
              {hero.secondaryCta.label} <ArrowIcon />
            </Link>
          </div>
        </div>
        <div className="hero-visual">
          <FacetSvg
            seed={HERO_FACET.seed}
            rings={HERO_FACET.rings}
            viewWidth={HERO_FACET.width}
            viewHeight={HERO_FACET.height}
            preserveAspectRatio="xMidYMid slice"
          />
          <div className="sheen" />
          <span className="caption">{hero.caption}</span>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 3: Write `AboutBlock.tsx`**

```tsx
import Link from 'next/link';

import { HOME_CONTENT } from '@/constants/homeContent';

import { ArrowIcon, Eyebrow, FacetSvg } from './primitives';

const { about } = HOME_CONTENT;

export default function AboutBlock() {
  return (
    <section className="section" id="about">
      <div className="wrap about-grid">
        <div className="about-visual">
          <FacetSvg seed={3} rings={4} viewWidth={400} viewHeight={500} />
        </div>
        <div className="about-content">
          <Eyebrow>{about.eyebrow}</Eyebrow>
          <h2>{about.heading}</h2>
          {about.paragraphs.map((paragraph) => (
            <p key={paragraph.slice(0, 32)}>{paragraph}</p>
          ))}
          <Link className="link-arrow" href={about.cta.href}>
            {about.cta.label} <ArrowIcon />
          </Link>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 4: Write `PillarsGrid.tsx`**

```tsx
import { HOME_CONTENT } from '@/constants/homeContent';

import { PILLAR_ICONS } from './icons';
import { Eyebrow } from './primitives';

const { pillars } = HOME_CONTENT;

export default function PillarsGrid() {
  return (
    <section className="section">
      <div className="wrap">
        <div className="section-head">
          <div>
            <Eyebrow>{pillars.eyebrow}</Eyebrow>
            <h2>{pillars.heading}</h2>
          </div>
        </div>
        <div className="pillars-grid">
          {pillars.items.map((item) => (
            <article className="pillar-card" key={item.title}>
              <svg className="pillar-icon" viewBox="0 0 32 32" fill="none" aria-hidden>
                {PILLAR_ICONS[item.icon]}
              </svg>
              <h3>{item.title}</h3>
              <p>{item.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 5: Write `EmpoweringList.tsx`**

```tsx
import Link from 'next/link';

import { HOME_CONTENT } from '@/constants/homeContent';

import { ArrowIcon, Eyebrow } from './primitives';

const { empowering } = HOME_CONTENT;

export default function EmpoweringList() {
  return (
    <section className="section">
      <div className="wrap">
        <div className="section-head">
          <div>
            <Eyebrow>{empowering.eyebrow}</Eyebrow>
            <h2>{empowering.heading}</h2>
          </div>
        </div>
        <div className="empower-list">
          {empowering.items.map((item, index) => (
            <div className="empower-row" key={item.title}>
              <div className="empower-num">{String(index + 1).padStart(2, '0')}</div>
              <div className="empower-main">
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </div>
              <Link className="link-arrow" href={item.href} aria-label={item.title}>
                <ArrowIcon />
              </Link>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 6: Write `ResourcesList.tsx`**

```tsx
import Link from 'next/link';

import { HOME_CONTENT } from '@/constants/homeContent';

import { LINE_ICONS } from './icons';
import { ArrowIcon, Eyebrow } from './primitives';

const { resources } = HOME_CONTENT;

export default function ResourcesList() {
  return (
    <section className="section" id="resources">
      <div className="wrap">
        <div className="section-head">
          <div>
            <Eyebrow>{resources.eyebrow}</Eyebrow>
            <h2>{resources.heading}</h2>
          </div>
        </div>
        <div className="resource-list">
          {resources.items.map((item, index) => (
            <div className="resource-row" key={item.title}>
              <svg className="resource-icon" viewBox="0 0 24 24" fill="none" aria-hidden>
                {LINE_ICONS[item.icon]}
              </svg>
              <span className="resource-num">{String(index + 1).padStart(2, '0')}</span>
              <div className="resource-main">
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </div>
              <Link className="link-arrow" href={item.href} aria-label={item.title}>
                <ArrowIcon />
              </Link>
            </div>
          ))}
        </div>
        <div className="resources-cta">
          <Link className="btn btn-primary" href={resources.cta.href}>
            {resources.cta.label} <ArrowIcon />
          </Link>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 7: Write `PartnersWall.tsx`**

```tsx
import Link from 'next/link';

import { HOME_CONTENT } from '@/constants/homeContent';

import { ArrowIcon, Eyebrow } from './primitives';

const { partners } = HOME_CONTENT;

export default function PartnersWall() {
  return (
    <section className="section section--surface">
      <div className="wrap">
        <div className="section-head">
          <div>
            <Eyebrow>{partners.eyebrow}</Eyebrow>
            <h2>{partners.heading}</h2>
            <p className="muted">{partners.intro}</p>
          </div>
        </div>
        <div className="partners-wall">
          {partners.items.map((name) => (
            <span className="partner-chip" key={name}>
              {name}
            </span>
          ))}
        </div>
        <Link className="link-arrow partners-cta" href={partners.cta.href}>
          {partners.cta.label} <ArrowIcon />
        </Link>
      </div>
    </section>
  );
}
```

Note: the reference sets `margin-top:14px;max-width:52ch` inline on this
paragraph. Add those two declarations to the `.da .section-head .muted` rule in
`site.css` instead of an inline style, so `MembersMarquee` gets them too.

- [ ] **Step 8: Write `MembershipCta.tsx`**

```tsx
import Link from 'next/link';

import { HOME_CONTENT } from '@/constants/homeContent';

import { LINE_ICONS } from './icons';
import { ArrowIcon, Eyebrow } from './primitives';

const { membership } = HOME_CONTENT;

export default function MembershipCta() {
  return (
    <section className="section section--dark" id="membership">
      <div className="wrap membership-grid">
        <div className="membership-content">
          <Eyebrow>{membership.eyebrow}</Eyebrow>
          <h2>{membership.heading}</h2>
          <p>{membership.body}</p>
          <div className="cta-group">
            <Link className="btn btn-primary--inverse" href={membership.primaryCta.href}>
              {membership.primaryCta.label}
            </Link>
            <Link className="link-arrow" href={membership.secondaryCta.href}>
              {membership.secondaryCta.label} <ArrowIcon />
            </Link>
          </div>
        </div>
        <div className="benefits-grid">
          {membership.benefits.map((benefit) => (
            <div className="benefit-item" key={benefit.label}>
              <svg viewBox="0 0 24 24" fill="none" aria-hidden>
                {LINE_ICONS[benefit.icon]}
              </svg>
              <span>{benefit.label}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 9: Write `FinalCta.tsx`**

```tsx
import Link from 'next/link';

import { HOME_CONTENT } from '@/constants/homeContent';

import { Eyebrow, FacetSvg } from './primitives';

const { finalCta } = HOME_CONTENT;

export default function FinalCta() {
  return (
    <section className="final-cta section" id="contact">
      <FacetSvg
        className="facet-bg"
        seed={21}
        rings={6}
        viewWidth={1440}
        viewHeight={500}
        dark
        preserveAspectRatio="xMidYMid slice"
      />
      <div className="wrap">
        <Eyebrow>{finalCta.eyebrow}</Eyebrow>
        <h2>{finalCta.heading}</h2>
        <p>{finalCta.body}</p>
        <div className="cta-group">
          <Link className="btn btn-primary--inverse" href={finalCta.primaryCta.href}>
            {finalCta.primaryCta.label}
          </Link>
          <Link className="btn btn-outline" href={finalCta.secondaryCta.href}>
            {finalCta.secondaryCta.label}
          </Link>
        </div>
      </div>
    </section>
  );
}
```

The reference puts `margin-top:14px` inline on this `<h2>`. Add
`.da .final-cta h2 { margin-top: 14px; }` to `site.css`.

- [ ] **Step 10: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

Expected: both pass.

- [ ] **Step 11: Commit**

```bash
cd customer && git add src/components/home src/components/site/site.css
git commit -m "feat(home): static homepage sections"
```

---

## Task 8: The dynamic homepage sections

**Files:**
- Create: `customer/src/components/home/StatsStrip.tsx`
- Create: `customer/src/components/home/UpcomingEvents.tsx`
- Create: `customer/src/components/home/IndustryGlance.tsx`
- Create: `customer/src/components/home/GlobalCommunity.tsx`
- Create: `customer/src/components/home/MembersMarquee.tsx`

**Interfaces:**
- Consumes: `useSiteStats`, `memberCount`, `countryCount`, `hubsFromStats`
  (Task 6); `EventService.listPublic` and `EventListItem` (existing);
  `eventTag`, `splitEventDate` (Task 3); primitives (Task 4).
- Produces: five default-exported section components. Task 9 composes them.

- [ ] **Step 1: Write `StatsStrip.tsx`**

```tsx
'use client';

import { STATIC_FIGURES } from '@/constants/homeContent';
import { countryCount, memberCount, useSiteStats } from '@/hooks/useSiteStats';

import { Reveal, StatNumber } from './primitives';

/**
 * The four figures under the hero.
 *
 * Two are ours and two are the industry's. The two that are ours are stated
 * exactly — the association knows how many members it has, and rounding a real
 * number up to a marketing one is the kind of small lie a trade body cannot
 * afford on its front page.
 */
export default function StatsStrip() {
  const { stats } = useSiteStats();

  const members = memberCount(stats);
  const countries = countryCount(stats);

  return (
    <section className="stats-strip">
      <div className="wrap stats-grid">
        <Reveal className="stat-item">
          <StatNumber
            value={STATIC_FIGURES.years.value}
            suffix={STATIC_FIGURES.years.suffix}
          />
          <div className="stat-label">Years of Industry Leadership</div>
        </Reveal>
        <Reveal className="stat-item">
          <StatNumber value={members.value} suffix={members.suffix} />
          <div className="stat-label">Members</div>
        </Reveal>
        <Reveal className="stat-item">
          <StatNumber value={countries.value} suffix={countries.suffix} />
          <div className="stat-label">Countries Represented</div>
        </Reveal>
        <Reveal className="stat-item">
          <StatNumber
            value={STATIC_FIGURES.globalTrade.value}
            prefix={STATIC_FIGURES.globalTrade.prefix}
            suffix={STATIC_FIGURES.globalTrade.suffix}
          />
          <div className="stat-label">Industry Represented</div>
        </Reveal>
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Write `UpcomingEvents.tsx`**

```tsx
'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { HOME_CONTENT } from '@/constants/homeContent';
import EventService, { type EventListItem } from '@/services/EventService';
import { splitEventDate } from '@/utils/home/eventDate';
import { eventTag } from '@/utils/home/eventTag';

import { ArrowIcon, Eyebrow, FacetSvg } from './primitives';

const { events } = HOME_CONTENT;

/** How many rows the design has room for. */
const LIMIT = 4;

/** The reference's per-row facet seeds, in order. */
const THUMB_SEEDS = [4, 11, 19, 27];

/**
 * The next four events, from the public list.
 *
 * The public endpoint, never the member one: a members-only event is *absent*
 * from that response rather than fetched and hidden, and this section is
 * rendered for a logged-out stranger.
 *
 * It renders nothing when there is nothing on. A homepage section headed
 * "Upcoming Events" with an empty state beneath it advertises that the
 * association has nothing planned.
 */
export default function UpcomingEvents() {
  const [rows, setRows] = useState<EventListItem[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let live = true;

    EventService.listPublic({ limit: LIMIT, open: true })
      .then((response) => {
        if (live) setRows(response.data.rows ?? []);
      })
      .catch(() => {
        // Silent, like the Newsroom block: one failed section must not become
        // the loudest thing on a page the visitor did not ask it for.
      })
      .finally(() => {
        if (live) setReady(true);
      });

    return () => {
      live = false;
    };
  }, []);

  if (!ready || rows.length === 0) return null;

  return (
    <section className="section" id="events">
      <div className="wrap">
        <div className="section-head">
          <div>
            <Eyebrow>{events.eyebrow}</Eyebrow>
            <h2>{events.heading}</h2>
          </div>
          <Link className="link-arrow" href={events.viewAll.href}>
            {events.viewAll.label} <ArrowIcon />
          </Link>
        </div>
        <div className="events-list">
          {rows.map((event, index) => {
            const date = splitEventDate(event.start_at);
            const tag = eventTag(event);

            return (
              <div className="event-row" key={event.id}>
                <div className="event-date">
                  {date.day}
                  <span>{date.monthYear}</span>
                </div>
                <div className="event-main">
                  <h3>{event.title}</h3>
                  <div className="event-meta">
                    {event.city ? <span className="event-loc">{event.city}</span> : null}
                    <span className={`tag tag--${tag.variant}`}>{tag.label}</span>
                    {event.event_type ? (
                      <span className="tag tag--neutral">{event.event_type}</span>
                    ) : null}
                  </div>
                </div>
                <Link className="link-arrow" href={`/events/${event.slug}`}>
                  View Event <ArrowIcon />
                </Link>
                <div className="event-thumb">
                  <FacetSvg
                    seed={THUMB_SEEDS[index % THUMB_SEEDS.length]}
                    rings={2}
                    viewWidth={200}
                    viewHeight={200}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 3: Write `IndustryGlance.tsx`**

```tsx
'use client';

import Link from 'next/link';

import { HOME_CONTENT, STATIC_FIGURES } from '@/constants/homeContent';
import { countryCount, memberCount, useSiteStats } from '@/hooks/useSiteStats';

import { ArrowIcon, Eyebrow, Reveal, StatNumber } from './primitives';

const { glance } = HOME_CONTENT;

/**
 * The trend line, copied from the reference verbatim.
 *
 * It is a drawing, not a plot: there is no series behind it (decision D-3), and
 * the caption under the chart says so. When the association supplies verified
 * figures, this path and that caption are what change.
 */
const TREND_LINE =
  'M0,190 L80,175 L160,178 L240,150 L320,140 L400,120 L480,110 L560,90 L640,70 L720,45 L800,30';
const TREND_AREA = `${TREND_LINE} L800,220 L0,220 Z`;

export default function IndustryGlance() {
  const { stats } = useSiteStats();

  const members = memberCount(stats);
  const countries = countryCount(stats);

  return (
    <section className="section section--surface" id="glance">
      <div className="wrap">
        <div className="section-head">
          <div>
            <Eyebrow>{glance.eyebrow}</Eyebrow>
            <h2>{glance.heading}</h2>
          </div>
        </div>

        <div className="glance-stats">
          <Reveal className="stat-item">
            <StatNumber
              value={STATIC_FIGURES.globalTrade.value}
              prefix={STATIC_FIGURES.globalTrade.prefix}
              suffix={STATIC_FIGURES.globalTrade.suffix}
            />
            <div className="stat-label">Global Trade</div>
          </Reveal>
          <Reveal className="stat-item">
            <StatNumber
              value={STATIC_FIGURES.annualProduction.value}
              suffix={STATIC_FIGURES.annualProduction.suffix}
            />
            <div className="stat-label">Annual Production</div>
          </Reveal>
          <Reveal className="stat-item">
            <StatNumber value={members.value} suffix={members.suffix} />
            <div className="stat-label">Association Members</div>
          </Reveal>
          <Reveal className="stat-item">
            <StatNumber value={countries.value} suffix={countries.suffix} />
            <div className="stat-label">Countries Represented</div>
          </Reveal>
        </div>

        <div className="chart-card">
          <div className="chart-head">
            <h3>{glance.chartTitle}</h3>
            <span className="chart-note">{glance.chartNote}</span>
          </div>
          <svg
            className="chart-svg"
            viewBox="0 0 800 260"
            preserveAspectRatio="none"
            role="img"
            aria-label="Line chart showing an illustrative upward trend in global diamond trade value from 2016 to 2026"
          >
            <g stroke="var(--da-border-strong)" strokeWidth="1">
              <line x1="0" y1="20" x2="800" y2="20" />
              <line x1="0" y1="80" x2="800" y2="80" />
              <line x1="0" y1="140" x2="800" y2="140" />
              <line x1="0" y1="200" x2="800" y2="200" />
            </g>
            <path d={TREND_AREA} fill="var(--da-accent)" opacity=".14" />
            <path d={TREND_LINE} fill="none" stroke="var(--da-accent-deep)" strokeWidth="2" />
            <circle cx="800" cy="30" r="5" fill="var(--da-dark)" />
            <text
              x="795"
              y="18"
              textAnchor="end"
              fontFamily="var(--da-font-mono)"
              fontSize="13"
              fill="var(--da-text)"
              fontWeight="600"
            >
              {`${STATIC_FIGURES.globalTrade.prefix}${STATIC_FIGURES.globalTrade.value}${STATIC_FIGURES.globalTrade.suffix}`}
            </text>
            <text x="0" y="245" fontFamily="var(--da-font-mono)" fontSize="11" fill="var(--da-text-secondary)">
              2016
            </text>
            <text x="770" y="245" fontFamily="var(--da-font-mono)" fontSize="11" fill="var(--da-text-secondary)">
              2026
            </text>
          </svg>
        </div>

        <Link className="link-arrow glance-cta" href={glance.cta.href}>
          {glance.cta.label} <ArrowIcon />
        </Link>
      </div>
    </section>
  );
}
```

- [ ] **Step 4: Write `GlobalCommunity.tsx`**

```tsx
'use client';

import { HOME_CONTENT, STATIC_FIGURES } from '@/constants/homeContent';
import { countryCount, hubsFromStats, memberCount, useSiteStats } from '@/hooks/useSiteStats';

import { Eyebrow, Reveal, StatNumber, WorldMap } from './primitives';

const { community } = HOME_CONTENT;

export default function GlobalCommunity() {
  const { stats } = useSiteStats();

  const members = memberCount(stats);
  const countries = countryCount(stats);
  const hubs = hubsFromStats(stats);

  return (
    <section className="section section--surface">
      <div className="wrap">
        <div className="section-head">
          <div>
            <Eyebrow>{community.eyebrow}</Eyebrow>
            <h2>{community.heading}</h2>
          </div>
        </div>

        <div className="map-card">
          <div className="map-canvas-wrap">
            <WorldMap hubs={hubs} />
          </div>
          <div className="map-legend">
            <span>
              <i /> {community.legendHub}
            </span>
            <span>{community.legendNote}</span>
          </div>
        </div>

        <div className="community-stats">
          <Reveal className="stat-item">
            <StatNumber value={countries.value} suffix={countries.suffix} />
            <div className="stat-label">Countries</div>
          </Reveal>
          <Reveal className="stat-item">
            <StatNumber value={members.value} suffix={members.suffix} />
            <div className="stat-label">Members</div>
          </Reveal>
          <Reveal className="stat-item">
            <StatNumber
              value={STATIC_FIGURES.partners.value}
              suffix={STATIC_FIGURES.partners.suffix}
            />
            <div className="stat-label">Global Partners</div>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 5: Write `MembersMarquee.tsx`**

```tsx
'use client';

import Link from 'next/link';

import { HOME_CONTENT } from '@/constants/homeContent';
import { useSiteStats } from '@/hooks/useSiteStats';

import { ArrowIcon, Eyebrow } from './primitives';

const { members } = HOME_CONTENT;

/**
 * Below this many names the marquee is not shown at all.
 *
 * The reference scrolls twelve logos. Three names looping past every eight
 * seconds does not read as a community — it reads as an empty association, so
 * the section removes itself until there is a wall to show. There is
 * deliberately no placeholder: inventing company names on the front page of a
 * trade body is not a design decision, it is a false claim.
 */
const MINIMUM = 6;

export default function MembersMarquee() {
  const { stats } = useSiteStats();

  const names = stats?.member_names ?? [];
  if (names.length < MINIMUM) return null;

  const group = (cloned: boolean) => (
    <div className="marquee-group" data-clone={cloned ? 'true' : undefined} aria-hidden={cloned}>
      {names.map((name) => (
        <div className="logo-cell" key={`${cloned ? 'clone' : 'row'}-${name}`}>
          <span>{name.toUpperCase()}</span>
        </div>
      ))}
    </div>
  );

  return (
    <section className="section">
      <div className="wrap">
        <div className="section-head">
          <div>
            <Eyebrow>{members.eyebrow}</Eyebrow>
            <h2>{members.heading}</h2>
            <p className="muted">{members.intro}</p>
          </div>
        </div>

        {/*
          The track is exactly two identical groups and the keyframe translates
          it by -50%, so the second group is under the cursor at the moment the
          animation resets and the loop has no seam. One group, or three, and
          the scroll visibly jumps.
        */}
        <div className="marquee">
          <div className="marquee-track">
            {group(false)}
            {group(true)}
          </div>
        </div>

        <Link className="link-arrow members-cta" href={members.cta.href}>
          {members.cta.label} <ArrowIcon />
        </Link>
      </div>
    </section>
  );
}
```

- [ ] **Step 6: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

Expected: both pass.

- [ ] **Step 7: Commit**

```bash
cd customer && git add src/components/home
git commit -m "feat(home): api-driven homepage sections"
```

---

## Task 9: Compose the homepage and verify the whole page

**Files:**
- Modify: `customer/src/app/(public)/page.tsx`

**Interfaces:**
- Consumes: every section component from Tasks 7 and 8.
- Produces: the finished route `/`.

- [ ] **Step 1: Replace the homepage**

Replace the whole of `customer/src/app/(public)/page.tsx` with:

```tsx
import type { Metadata } from 'next';

import AboutBlock from '@/components/home/AboutBlock';
import EmpoweringList from '@/components/home/EmpoweringList';
import FinalCta from '@/components/home/FinalCta';
import GlobalCommunity from '@/components/home/GlobalCommunity';
import HomeHero from '@/components/home/HomeHero';
import IndustryGlance from '@/components/home/IndustryGlance';
import MembersMarquee from '@/components/home/MembersMarquee';
import MembershipCta from '@/components/home/MembershipCta';
import PartnersWall from '@/components/home/PartnersWall';
import PillarsGrid from '@/components/home/PillarsGrid';
import ResourcesList from '@/components/home/ResourcesList';
import StatsStrip from '@/components/home/StatsStrip';
import UpcomingEvents from '@/components/home/UpcomingEvents';

export const metadata: Metadata = {
  title: 'Home',
  description:
    'The association representing, connecting and advancing businesses and professionals across the global diamond industry.',
};

/**
 * The public homepage.
 *
 * Section order is the reference design's, unchanged. Each section owns its own
 * data: the ones that fetch do so from a client component, so this page stays
 * static and a slow or failed API call costs a section rather than the page.
 */
export default function HomePage() {
  return (
    <>
      <HomeHero />
      <StatsStrip />
      <UpcomingEvents />
      <AboutBlock />
      <PillarsGrid />
      <EmpoweringList />
      <IndustryGlance />
      <ResourcesList />
      <GlobalCommunity />
      <MembersMarquee />
      <PartnersWall />
      <MembershipCta />
      <FinalCta />
    </>
  );
}
```

- [ ] **Step 2: Verify types, lint and helpers**

```bash
cd customer && npm run typecheck && npm run lint && npm run verify:home
```

Expected: all three pass.

- [ ] **Step 3: Build**

```bash
cd customer && npm run build
```

Expected: a successful build with `/` listed in the route table. A hydration
warning about `FacetSvg` means the generator is not deterministic between server
and client — re-check Task 3 Step 1.

- [ ] **Step 4: Verify against the reference, side by side**

With the backend running and the customer dev server up, open
`docs/superpowers/specs/2026-08-31-public-homepage-reference.html` directly in
one browser tab and `http://localhost:3000/` in another, and compare at three
widths — 1440px, 1024px and 390px. Walk this list:

- [ ] Header: sticky, translucent, 76px, underline grows on nav hover
- [ ] Hero: facet diamond identical to the reference, sheen sweeps, caption pill
- [ ] Stats strip: counts up once at 50% visibility; Members and Countries show
      **real** numbers with no `+`; Years and Industry show `50+` and `$80B+`
- [ ] Events: real events, correct date split, correct tag colour, thumbnail
      fades in on row hover, whole section absent when there are no open events
- [ ] About: 4:5 facet panel left, copy right
- [ ] Pillars: 3 / 2 / 1 columns, hairline grid, hover fill
- [ ] Empowering: numbered rows, arrow slides right on hover
- [ ] Glance: 4 stats, chart card, trend line and `$80B+` label
- [ ] Resources: 6 rows, icons, hover fill, dark CTA button centred
- [ ] Community: map draws, dots on the countries we have members in, redraws on
      window resize, 3 stats below
- [ ] Members: marquee scrolls 48s, pauses on hover, edge mask, no seam at the
      loop point; section absent when fewer than 6 names
- [ ] Partners: chips wrap, border darkens on hover
- [ ] Membership: dark section, 2×3 benefits grid, inverse button
- [ ] Final CTA: dark facet background at 50% opacity, centred, two buttons
- [ ] Footer: 5 columns → 2 → 1, legal row

- [ ] **Step 5: Verify reduced motion**

In the browser devtools, enable "Emulate CSS prefers-reduced-motion: reduce",
reload `/` and confirm:
- stats show their final value immediately, no count-up
- `[data-reveal]` blocks are visible immediately, no fade
- the hero sheen does not animate
- the marquee does not scroll, the clone group is hidden, and the strip scrolls
  horizontally by hand instead
- the map draws its dots with no halos
- smooth scrolling is off

- [ ] **Step 6: Verify keyboard and screen-reader basics**

- [ ] Tab from the address bar: the skip link appears first and jumps to `#main`
- [ ] Every nav item, button and row link is reachable and shows the focus ring
- [ ] The hamburger reports `aria-expanded` correctly and the panel closes on
      link activation
- [ ] The canvas has its `aria-label`; the decorative facet SVGs are `aria-hidden`

- [ ] **Step 7: Commit**

```bash
cd customer && git add "src/app/(public)/page.tsx"
git commit -m "feat(home): assemble the redesigned public homepage"
```

---

## Self-Review Notes

Checked against the spec on completion of writing:

- Spec §3's table has a task for every row: static sections in Task 7, dynamic
  in Task 8, the endpoint behind them in Task 1.
- Spec §4.1's link map is realised in `homeContent.ts` (Task 3 Step 6) and in
  `SITE_NAV` / `SITE_FOOTER_COLUMNS`.
- Spec §4.2 (brand name from settings) is **deliberately deferred**: the
  homepage uses `SITE_NAME_FALLBACK` rather than fetching `/public/settings`.
  Fetching a display name to render the logo would block the header on a request
  on every public page. If the association's real name differs from
  "Diamond Association", change the one constant in `homeContent.ts`. Flagged
  here rather than silently dropped.
- Spec §4.3's omission of the event description is reflected in
  `UpcomingEvents.tsx`, which renders no `.event-desc`. The `.event-desc` rule
  is still ported in Task 2 so the row spacing matches if a description field is
  added later.
- Spec §5's tag rules are implemented in `eventTag.ts` and asserted in
  `verify-home-helpers.ts`.
- Spec §6's behaviour list maps to: `SiteHeader` (sticky, mobile nav),
  `StatNumber` (count-up), `Reveal`, `FacetSvg`, `site.css` (sheen, marquee,
  hover), `WorldMap` (canvas, resize, DPR), and the reduced-motion checks in
  Task 9 Step 5.
- Type consistency: `Hub` is defined once in `worldMap.ts` and consumed by
  `useSiteStats.ts` and `WorldMap.tsx`; `SiteStats` is defined in
  `SiteService.ts` on the customer side and mirrors `site.types.ts` on the
  backend; `EventListItem` is the existing exported type and is not redefined.
