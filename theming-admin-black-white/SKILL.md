---
name: theming-admin-black-white
description: Use when restyling, theming, or improving UI/UX of the Aigiri admin panel (aigiri-admin-app) — subtle black-and-white / monochrome / ElevenLabs-like theme; sidebar, header, app shell layout; tables, sorting, filtering, pagination; Ant Design component chrome; spacing density; or when admin screens look cluttered, inconsistent, poorly aligned, or hard to scan.
---

# Theming the admin panel (black-white, ElevenLabs-close)

Operator-grade admin UI. Light-first monochrome chrome, close to [elevenlabs.io/app](https://elevenlabs.io/app). Color is reserved for meaning (status, charts, deltas). Layout, tables, and density are in scope.

**Repo:** `aigiri-admin-app` only. Do not touch store-app, web-app, or backend.

Read these before editing, in this order:

1. This file (workflow + hard rules)
2. [palette.md](palette.md) — tokens, surfaces, what may be colorful
3. [layout.md](layout.md) — shell, sidebar, header lining, spacing
4. [tables.md](tables.md) — headers, sort, filter, pagination
5. [components.md](components.md) — Ant Design + shared components

## Core principle

Analyze what the current theme actually is, then rebuild chrome, layout, and components into a **subtle** black-and-white system. Do not assume the existing palette. Do not pitch-black large surfaces. Do not waste space. Every screen must feel like a tool an operator uses all day.

## Hard rules

- **Analyze first.** Inventory current tokens, ConfigProvider, CSS variables, hardcoded hex/rgba/`[#hex]`, and component chrome before changing anything.
- **Subtle ink, not pitch black.** Large surfaces, sidebars, headers, table headers, drawers, and overlays never use `#000000`. Prefer `#171717` for text and `#262626` for primary fills. `#0a0a0a` is allowed only on a primary CTA fill if contrast needs it. See [palette.md](palette.md).
- **Chrome is monochrome.** Buttons, inputs, menus, tabs, borders, focus rings, cards, sidebar, header, table chrome, pagination chrome — greys and near-black only.
- **Meaning may be colorful.** Status badges, KPI deltas, chart series, QC pass/fail, payment/order state — use the universal semantic colors in [palette.md](palette.md). Do not grey these out.
- **Components follow the theme.** Theming tokens is not enough. Ant Design, custom tables, drawers, modals, tags, switches, and page wrappers must match.
- **Layout is in scope.** Left sidebar with even tab spacing; top header that lines up with the sidebar logo row; content that uses leftover space instead of dumping padding.
- **Tables are a product surface.** Headers, sort, filter, and pagination are required on data tables. See [tables.md](tables.md).
- **Density over decoration.** Tight, even spacing. No luxury voids. No 40px gaps where 12px works.
- **No functionality change** except missing table sort / filter / pagination / empty states needed for the UX contract.
- **Leave imagery.** Logos, product photos, payment-provider icons — no greyscale filters.
- **Retarget tokens in place.** Keep class names (`bg-primary`, `text-secondary`, CSS vars). Change the values they resolve to. Do not rename tokens.
- **Do not frame the work as swapping a previous brand palette.** Describe it as: analyze current theme → apply this system.

## Workflow

Copy and track:

```
Admin UI pass:
- [ ] 1. Analyze current theme
- [ ] 2. Analyze current shell / layout / density
- [ ] 3. Analyze tables (sort / filter / pagination gaps)
- [ ] 4. Retarget theme sources
- [ ] 5. Rebuild app shell (sidebar + header lining + content)
- [ ] 6. Theme components
- [ ] 7. Apply semantic color only where required
- [ ] 8. Sweep hardcoded chrome colors
- [ ] 9. Table UX pass
- [ ] 10. Density + contrast audit
- [ ] 11. Visual QA
```

### 1. Analyze current theme

Do not skip this. Write down (in the conversation, briefly) what is actually driving color today:

Theme sources (read all):

- `tailwind.config.js`
- `src/styles/index.css` (`:root`)
- `src/styles/tailwind.css`
- `src/styles/ants.css`
- `src/app/layout.tsx` (`ConfigProvider` / `customTheme`)

Then search:

```bash
rg -n "colorPrimary|#[0-9a-fA-F]{3,8}|rgba\(|bg-\[#|text-\[#|border-\[#" src --glob '!*.svg' | head -200
```

Classify every hit as:

| Class | Action |
| --- | --- |
| Chrome (buttons, borders, nav, inputs, focus, cards, headers) | Map to monochrome tokens |
| Semantic (status, pass/fail, delta, chart series) | Map to universal semantic colors |
| Imagery / logo | Leave |
| Dead / unused | Ignore |

Record which token names exist and what they currently resolve to. Then map each name onto the palette in [palette.md](palette.md) by **role** (page bg, surface, border, body text, muted, CTA), not by guessing.

### 2. Analyze current shell

Read:

- `src/app/layout.tsx`
- `src/components/Sidebar1/index.tsx`
- `src/components/Header/index.tsx`
- `src/components/Wrepper/index.tsx`

Known structural problems to treat as defects (verify they still exist, then fix):

- Sidebar width is a percentage (`14%`) instead of a fixed `240px` / collapsed `64px`
- Main width is `85%` / `95%` instead of `flex-1 min-w-0`
- App shell in `layout.tsx` has no content header; `Header` exists but is unused; `Wrepper` would double-mount the sidebar — do not use `Wrepper` as-is
- Sidebar logo row and content header do not share a horizontal hairline
- Nav items are cramped (`height: 32px`, `margin: 2px`) and selected state uses a colored left bar
- Pages each re-apply `bg-[#f9f9f9] p-5 min-h-[calc(100vh-80px)]` instead of one shell background

Rebuild to the shell in [layout.md](layout.md).

### 3. Analyze tables

For each data table you touch (and when doing a full pass: sample Orders, Users, Inventory, Vendors, plus one Master list):

- Sortable columns?
- Search / filters that match the data?
- Pagination with total, page size, current page?
- Sticky header? Horizontal scroll? Empty state?
- Header/cell padding consistent?

Fix to the contract in [tables.md](tables.md).

### 4. Retarget theme sources

Order:

1. `src/app/layout.tsx` Ant Design `token`
2. `src/styles/index.css` `:root`
3. `tailwind.config.js` `theme.extend.colors`
4. `src/styles/tailwind.css` ramps
5. `src/styles/ants.css` component overrides

Keep names. Change values. After remap, fix any pair that becomes ink-on-ink or grey-on-grey.

### 5–11

Follow [layout.md](layout.md), [components.md](components.md), [tables.md](tables.md). Then sweep remaining hardcoded chrome hex. Then density + contrast. Then the QA list below.

## User perspective (non-negotiable)

The user is an operator scanning lists, changing status, and finding exceptions.

- **Find, don't decorate.** Status color and type weight carry meaning. Chrome stays quiet.
- **Scan path:** sidebar (where am I) → header (what is this page) → filters → table → pagination. Nothing jumps in front of that path.
- **Don't make them hunt.** Pagination sits on the table, not a scroll later. Active filters show as chips. Sortable headers look sortable.
- **Don't shout.** A selected nav item is a grey pill, not a colored slab. A primary button is one near-black fill, not a glowing block.
- **Don't waste the viewport.** Table body fills leftover height. Padding is even and small. Whitespace is a separator, not a feature.
- **Don't break attention with pitch black.** A large `#000` panel in an otherwise light tool is a visual trap. Keep the room light; use near-black only on the control they should click.

## Visual target (ElevenLabs-close)

Match this feel, not a pixel-perfect clone:

- Light grey sidebar, white main, hairline borders (`1px #e5e5e5`)
- Logo row and header are the **same height** with one continuous bottom border across the app
- Selected nav: filled grey rounded item, ink text, **no** colored accent bar
- Primary button: near-black fill, white label, hover slightly lighter
- Inputs: white, grey border, focus ring near-black at low opacity
- Cards/tables: white, 1px border, radius 8–12px, almost no shadow
- Type: 13px body, 11–12px meta/headers, 18–20px page title

If a choice is "more brand" vs "more ElevenLabs admin", pick ElevenLabs admin.

## What not to do

| Excuse | Reality |
| --- | --- |
| "I'll just swap the accent to black" | Analyze first. Layout, tables, and components are in scope. |
| "Black theme means `#000` sidebar" | Light-first. Sidebar is `#fafafa`. |
| "Statuses should go grey too" | Status, charts, and required meaning keep universal color. |
| "More padding looks premium" | This is an ops tool. Tight, even, useful. |
| "Rename tokens to ink/surface" | Retarget values. Names stay. |
| "Header is unused, skip it" | Build the lined shell. |
| "Sort/filter is a feature, not theme" | Table UX is part of this skill. |
| "Greyscale the logo so it matches" | Leave imagery. |

## Visual QA

Walk at least: Login, Dashboard, Orders, one Master list, one form/drawer.

- [ ] No colored chrome (buttons, nav, focus, tabs, table header bg)
- [ ] No pitch-black surfaces except a primary CTA fill
- [ ] Sidebar tabs evenly spaced; selected item is a grey pill
- [ ] Header hairline continues from the sidebar logo row
- [ ] Page title + actions share one row; filters the next; table uses the rest
- [ ] Table headers aligned; sort icons visible on sortable columns
- [ ] Filters match the table; chips show what is on
- [ ] Pagination: total, range, page size, current page; right-aligned on the table
- [ ] Status/chart color still readable and semantic
- [ ] Hover, focus, disabled, and selected are distinct without using hue in chrome
- [ ] No large empty bands; no overlapping borders; no double page backgrounds
- [ ] Keyboard focus visible (near-black ring, not browser blue)

## Out of scope

- Dark mode
- Store-app, web-app, backend
- API / permission / business-logic changes
- Rewriting tables to a new library when Ant Table can meet the contract
