# Layout — shell, lining, density

The current admin feels loose and misaligned because the shell is percentage-based, the header is missing from the live tree, and every page re-paints its own background. Fix the shell once. Pages consume it.

## App shell

```
┌────────────────┬────────────────────────────────────────┐
│ LOGO     [«]   │  Page title              actions  avatar│  ← 56px, ONE hairline
├────────────────┼────────────────────────────────────────┤
│ OVERVIEW       │                                        │
│   Dashboard    │  filters / tabs                        │
│                │                                        │
│ ORDERS         │  table / form                          │
│   …            │  (fills leftover height)               │
│                │                                        │
│ ────────────── │  pagination sits on the table          │
│ Avatar  User   │                                        │
└────────────────┴────────────────────────────────────────┘
```

### Structure (`src/app/layout.tsx`)

```
body: h-screen overflow-hidden background #fafafa
.flex h-screen w-full
  Sider     flex-none, 240px (64px collapsed), h-screen, overflow-hidden
  .flex.flex-col.flex-1.min-w-0.h-screen
    Header  flex-none, h-14 (56px), z-20
    main    flex-1 min-h-0 overflow-y-auto
```

Rules:

- **No percentage widths.** Sidebar `240px` / `64px`. Main `flex-1 min-w-0`.
- **No `contentWidth = collapsed ? '95%' : '85%'`.**
- Public routes (`/login`, `/register`, `/forgot-password`): no sider, no app header; centered card on `#fafafa`.
- Mobile: drawer sidebar, hamburger in the header left, not a free-floating icon over content.
- Do not mount `Wrepper` — it double-renders `Sidebar1` + `Header` on top of `layout.tsx`.

### The lining (critical)

Sidebar logo row and content header are **the same 56px** and share **one continuous 1px `#e5e5e5` bottom border**.

- Sidebar logo row: `h-14`, `px-4`, `flex items-center`, `border-b border-[#e5e5e5]`, `bg-[#fafafa]`
- Header: `h-14`, `px-6`, `flex items-center`, `border-b border-[#e5e5e5]`, `bg-[#ffffff]`, **no drop shadow**
- Collapse control lives on the logo row (right), vertically centered with the logo — not a floating circle that breaks the line
- Header left padding `24px` equals page content padding so title lines up with the page, not with the sidebar edge

If those two bars are different heights or one has a shadow and the other a border, the app looks broken. Fix lining before theming buttons.

## Sidebar

Width `240px` expanded, `64px` collapsed. Background `#fafafa`. Right border `1px #e5e5e5`. No box-shadow.

### Nav items

| Spec | Value |
| --- | --- |
| Item height | `36px` |
| Horizontal inset | `8px` on the menu, item `padding 0 10px` |
| Gap between items | `4px` |
| Radius | `8px` |
| Icon | `16px`, `margin-right 10px`, currentColor |
| Label | `13px`, `font-weight 450` inactive / `600` selected |
| Group label | `11px`, uppercase, `letter-spacing 0.06em`, `#a3a3a3`, `padding 16px 10px 6px` |
| First group | `padding-top 10px` (not 24px) |

**Selected:** background `#ececec`, text `#171717`, icon `#171717`. **No left accent bar. No tinted fill.**

**Hover (not selected):** background `#f0f0f0`.

**Collapsed:** icon-only, `36×36` hit target centered; selected = grey square, not a colored icon.

**BETA / MOCK badges:** keep semantic colors (info / warning). They are meaning, not chrome. Size `9–10px`, do not inflate the row.

### Sidebar footer (user)

Pinned to bottom, `border-top 1px #e5e5e5`, `px-3 py-3`, avatar `32px`, name `13px #171717`, email `11px #737373` truncated. Logout in the dropdown. Do **not** also dump name/email into the header — pick sidebar for identity (ElevenLabs). Header may show a small avatar that opens the same menu.

Scroll: only the menu list between logo row and footer (`calc(100vh - 56px - footer)`). Footer never scrolls away.

## Header

White, 56px, hairline bottom, no shadow.

Left (in order, omit empty):

1. Current page title (`16–18px`, semibold, `#171717`) **or** breadcrumb if the page is nested (`13px`, muted parents, ink current)
2. Optional context (store name, environment) as muted `12px`

Right, `gap-8px`, vertically centered:

1. Page-level actions (secondary then primary)
2. Optional `1px × 16px` divider `#e5e5e5`
3. Avatar `28px`

Do not rebuild the old Header that only shows a name and a vertical grey rule with no title. The header must tell the user **which page** they are on.

Page titles in the header **or** in the page body — not both competing. Prefer:

- Header: section title (Orders)
- Body: no duplicate H1; start at filters / KPIs

If a page already has a local `<Heading>`, keep one source. Remove the duplicate.

## Page body

Shell owns `#fafafa`. Pages must **stop** wrapping themselves in `bg-[#f9f9f9] p-5 min-h-[calc(100vh-80px)]`. That double background and fake min-height is why screens look patchy.

Shared page padding:

```
px-6 py-5   /* 24px / 20px */
display flex; flex-direction column; gap-4; /* 16px between major blocks */
min-height 100%
```

### Page anatomy (list screens)

1. **Optional KPI row** — 4 columns, `gap-12px`. Compact cards, `padding 12px 14px`, not dashboard-hero.
2. **Toolbar** — one row: search left (`max-width 320–360px`); filters, date, primary action right; `gap-8px`. Wrap only below 1100px.
3. **Active filter chips** — directly under toolbar, `gap-6px`, `12px` type. No extra 24px margin.
4. **Table card** — `flex-1 min-h-0`, white, `1px #e5e5e5`, radius `10px`. Table body scrolls inside.
5. **Pagination** — inside the card footer, right-aligned, `padding 8px 12px`, top border `#e5e5e5`. Never a lonely control in the page margin.

### Form / detail screens

- Max readable width for forms: `720px` for single-column; full width for multi-column masters.
- Section gap `16px`. Field gap `12px`. Label `12px #737373` above control.
- Sticky footer actions in drawers (`padding 12px 16px`, top border), not a primary button lost in the scroll.

## Spacing scale

Use 4px. Do not invent 18px / 22px / 26px.

| Token | px | Use |
| --- | --- | --- |
| 1 | 4 | Icon-to-label in dense chips |
| 2 | 8 | Control gap in a toolbar, cell y-padding |
| 3 | 12 | Card padding, field gap, table cell x-padding |
| 4 | 16 | Block gap (KPI → toolbar → table) |
| 5 | 20 | Page vertical padding |
| 6 | 24 | Page horizontal padding, header x-padding |

**Forbidden density mistakes**

- `p-10` / `py-16` empty states that shove the table off-screen — empty state `py-10` max
- `gap-8` (32px) between a title and a table
- Sidebar item `height 32px` + `margin 2px` (too cramped to click comfortably) **and** `height 48px` + `margin 12px` (too sparse)
- Cards with `24px` padding around a `12px` KPI label
- Horizontal padding on main `40px+` while the table needs width

**Rule:** if a region is empty enough to notice, it is too empty. Pull content up. If two controls collide, add `8px`, not `24px`.

## Radius and type

| Surface | Radius |
| --- | --- |
| Buttons, inputs, nav items | `8px` |
| Cards, tables, drawers | `10px` |
| Pills / status tags | `999px` |
| Checkboxes | `4px` |

Type (Avenir LT Pro already in the app):

| Role | Size | Weight | Color |
| --- | --- | --- | --- |
| Page title | 18px | 600 | `#171717` |
| Section | 14px | 600 | `#171717` |
| Body / table cell | 13px | 400 | `#171717` |
| Table header | 11px | 600 | `#737373` uppercase, tracking `0.04em` |
| Meta / help | 12px | 400 | `#737373` |
| Group label | 11px | 600 | `#a3a3a3` uppercase |

Line-height `1.4` for body. Do not keep global `line-height: normal` on table cells if it clips glyphs — `20px` line-height on 13px cells.

## Login

Centered card `400–440px`, white, `1px #e5e5e5`, radius `10px`, `padding 32px`, logo above, title `18px`, primary submit full width near-black. Canvas `#fafafa`. No colored panel behind the card.
