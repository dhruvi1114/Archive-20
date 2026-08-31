# Public Homepage Redesign — Design Spec

**Date:** 2026-08-31
**Reference design:** [`2026-08-31-public-homepage-reference.html`](./2026-08-31-public-homepage-reference.html)
**Applies to:** `customer/` (Next.js public site) and one new read-only backend endpoint.

---

## 1. What this is

The client supplied a finished, self-contained HTML page for the association's
public homepage. We are reproducing it **pixel-for-pixel and behaviour-for-behaviour**
inside the Next.js customer app, with the sections that have real data in our
database driven by the API instead of the hardcoded demo content.

"Exact same design" is the acceptance bar. Where this document and the reference
HTML disagree, **the reference HTML wins** — except for the explicit substitutions
listed in §4.

## 2. Decisions taken (client, 2026-08-31)

| # | Question | Decision |
|---|----------|----------|
| D-1 | How far does the new design go? | **Homepage + a new public header and footer.** The reference header/footer replace `PublicHeader`/`PublicFooter` for every page in `app/(public)`. Other public pages keep their current body styling for now. |
| D-2 | Dark mode? | **Light-only.** The homepage and the new public shell always render in the reference palette regardless of the theme toggle. The toggle continues to work on member pages. |
| D-3 | Figures with no data source (years, global trade, production, chart, partners) | **Static.** Hardcoded in one constants file in `customer/`. No admin screen, no DB table. |
| D-4 | Figures we *can* compute (members, countries, hub cities) | **Dynamic**, from a new public API endpoint. Aggregate counts only — never a list of who they are. |
| D-5 | The reference's "Our Members" name marquee | **Removed** (decided 2026-08-31, after D1 in `client-decisions.md` made the member directory members-only). Publishing member company names on the public homepage is the same disclosure the directory decision refused. The `directory_visible` tick-box is consent to appear *in the members' directory*, not consent to appear on a public, Google-indexed front page; reusing it for the homepage would stretch consent past what the member agreed to. Aggregate figures stay — a count discloses nothing about any individual company. |

## 3. Section-by-section data source

Sections are listed in the order they appear in the reference HTML.

| Section | Source | Notes |
|---|---|---|
| Header | Static nav, real routes | Nav links go to real pages, not `#anchors` (§4.1) |
| Hero | Static copy + generative facet SVG | Verbatim from reference |
| Stats strip — Years of Industry Leadership | **Static** (`50+`) | D-3 |
| Stats strip — Members | **API** `stats.members` | Falls back to static when the call fails |
| Stats strip — Countries Represented | **API** `stats.countries` | Falls back to static |
| Stats strip — Industry Represented | **Static** (`$80B+`) | D-3 |
| Upcoming Events | **API** `GET /public/events?limit=4&open=true` | Existing endpoint, already used by `/events` |
| About | Static copy | Verbatim |
| What We Stand For (6 pillars) | Static | Verbatim |
| Empowering the Industry (4 rows) | Static | Verbatim |
| The Industry at a Glance — 4 stats | 2 static (`$80B+`, `130M+`), 2 **API** (members, countries) | |
| The Industry at a Glance — chart | **Static** SVG path | D-3. Verbatim from reference |
| Knowledge & Resources (6 rows) | Static labels, real routes | The rows are navigation, not content |
| Global community map | Static continent shapes + **API** `stats.hubs` for the dots | Falls back to the reference's 8 demo hubs |
| Community stats (Countries / Members / Global Partners) | 2 **API**, 1 **static** (`40+` partners) | |
| ~~Our Members marquee~~ | **Removed — D-5** | The section and the `stats.member_names` field are both dropped. No endpoint returns member names to an anonymous caller. |
| Our Partners wall | **Static** list of 10 chips | D-3 |
| Membership CTA + 6 benefits | Static | Verbatim |
| Final CTA | Static | Verbatim |
| Footer | Static, real routes | |

## 4. Deliberate substitutions from the reference

These are the only places we knowingly diverge.

### 4.1 Links become real routes

Every `href="#anchor"` in the reference is a placeholder. Mapping:

| Reference `href` | Real route |
|---|---|
| `#top` (logo, Home) | `/` |
| `#about` | `/about` |
| `#membership` | `/membership` |
| `#events`, "View All Events" | `/events` |
| `#resources`, "News & Insights" | `/news` |
| `#contact` (Member Login) | `/login` |
| "Become a Member" | `/signup` |
| "Explore Member Directory" | `/directory` — relabelled **"Member Directory — members only"**. The route lives behind the member login (see `docs/specs/2026-08-31-member-directory.md`), so an anonymous visitor reaches a sign-in wall. The button stays: a visible, honestly-labelled locked benefit advertises membership. |
| `mailto:info@diamondassociation.org` | `/contact` |
| Per-event "View Event" | `/events/{slug}` |

The in-page anchors that are genuinely in-page (`#glance` for the "Industry" nav
item, `#main` for the skip link) stay as anchors.

### 4.2 Brand name

The reference hardcodes "DIAMOND ASSOCIATION". The homepage reads it from a
constant (`SITE_NAME_FALLBACK` in `customer/src/constants/homeContent.ts`) rather
than fetching `/public/settings` — blocking the header of every public page on a
request just to render a display name is not worth it. Changing the association's
name is a one-line edit. The eyebrow "Global Industry Body" stays static.

### 4.3 Event row content

The reference invents event copy. Real fields map as:

| Reference element | Real field |
|---|---|
| `24` / `SEP 2026` | `start_at`, formatted |
| Title | `title` |
| `Mumbai, India` | `city` (omit the row when null) |
| `Registration Open` / `Limited Seats` | derived — see §5 |
| `Conference` tag | `event_type` (omit the tag when null) |
| Description paragraph | **omitted** — the list endpoint has no description field. The row keeps its date/title/meta and is one line shorter. |

### 4.4 Fonts

The reference loads Geist and Geist Mono from Google Fonts. We must **not** add a
Google Fonts link: `customer/src/app/layout.tsx` already self-hosts Geist via
`next/font/local`. Geist Mono is not currently self-hosted — see Task 2 of the plan.

### 4.5 Dynamic figures are stated exactly

The reference rounds every figure up to a marketing number (`500+`, `30+`). A
count we actually hold is rendered **exactly and without the `+`** — 512 members
renders as `512`. Rounding a real number up to a marketing one is a small lie a
trade body cannot afford on its front page. The static figures keep their `+`,
`$` and `B+` affixes exactly as the reference has them.

### 4.6 Sections that would be empty remove themselves

Following the existing `NewsroomBlock` precedent:

- **Upcoming Events** renders nothing when the public list is empty or fails.
- **Our Members** is removed entirely (D-5), so there is no empty-state rule for
  it. The reference's 12 demo company names must not ship as fallback content
  either: inventing company names on a trade body's front page is a false claim,
  not a design decision.
- **Stats** fall back to the association's own published figures on failure,
  never to an error panel.

## 5. Event status tag rules

The reference shows three tag styles. Derive them from `EventListItem`:

```
seats_left !== null && seats_left <= 0          -> "Sold Out"           tag--neutral
seats_left !== null && seats_left <= 20         -> "Limited Seats"      tag--warning
registration_closes_at && now > closes_at       -> "Registration Closed" tag--neutral
otherwise                                       -> "Registration Open"  tag--success
```

The "Invitation Only" tag in the reference has no equivalent field and is dropped.

## 6. Behaviour that must be preserved exactly

- Sticky translucent header with `backdrop-filter: blur(10px)`
- Mobile nav: full-screen overlay below the 76px header, body scroll locked, closes on link click, `aria-expanded` kept in sync
- Count-up stat animation, triggered once at 50% visibility, 1400ms, cubic ease-out
- `[data-reveal]` fade-and-rise, triggered once at 30% visibility
- Generative low-poly facet SVGs (hero, about, final CTA background, per-event hover thumbnails) — the seeded PRNG must produce the same output as the reference
- Hero sheen sweep, 7s loop
- Marquee: 48s linear scroll, duplicated group, pauses on hover, edge mask
- Event row hover: background lift + facet thumbnail fade-in
- Generative canvas world map, redrawn on resize (150ms debounce) and on entering the viewport, DPR-aware
- **Every** `prefers-reduced-motion: reduce` branch in the reference CSS and JS

## 7. Non-goals

- No admin screen for any homepage content (D-3)
- No `Partner` table
- No changes to `/events`, `/news`, `/about`, `/membership` page bodies
- No dark palette for the public shell (D-2)
- No accounting integration (project-wide scope rule)

## 8. Open questions

None blocking. If the association later wants the static figures editable, the
constants file in §3 is the single place that becomes an API call.
