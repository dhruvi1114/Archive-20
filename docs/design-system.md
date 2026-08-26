# Design System

One monochrome token set, two densities: **Customer** (spacious, mobile-first — FR-22 makes responsiveness contractual) and **Admin** (dense, high signal). Same components, same palette, different spacing scale. Visual direction per the user: ElevenLabs-style black and white — near-black on white, hairline borders, generous whitespace, no decorative colour.

## 1. Foundations

### Colour system — monochrome (user direction, 2026-08-12: ElevenLabs-style black & white)

Chrome is greyscale. Colour appears only where it carries meaning (status), never for decoration. Hierarchy comes from weight, size, spacing and hairline borders — not from hue.

**Neutral scale** (the whole design system, essentially):

| Token | Light | Dark | Use |
|---|---|---|---|
| `--n-0` | `#FFFFFF` | `#0A0A0A` | page background |
| `--n-50` | `#FAFAFA` | `#111111` | subtle fill, table header, hover row |
| `--n-100` | `#F5F5F5` | `#171717` | input background, disabled fill |
| `--n-200` | `#E5E5E5` | `#262626` | **hairline borders, dividers** |
| `--n-300` | `#D4D4D4` | `#333333` | input border, focus ring base |
| `--n-400` | `#A3A3A3` | `#525252` | placeholder, disabled text |
| `--n-500` | `#737373` | `#737373` | secondary text, captions |
| `--n-700` | `#404040` | `#A3A3A3` | body text on subtle surfaces |
| `--n-900` | `#171717` | `#EDEDED` | headings, primary text |
| `--n-1000` | `#0A0A0A` | `#FFFFFF` | **primary action fill**, max-contrast text |

**Semantic roles**

| Role | Light | Dark |
|---|---|---|
| `--bg` | `--n-0` | `--n-0` |
| `--surface` | `#FFFFFF` | `#141414` |
| `--fg` | `--n-900` | `--n-900` |
| `--fg-muted` | `--n-500` | `--n-500` |
| `--border` | `--n-200` | `--n-200` |
| `--primary` (button fill) | `--n-1000` (black) | `#FFFFFF` (white) |
| `--primary-fg` (button text) | `#FFFFFF` | `#0A0A0A` |
| `--focus-ring` | `--n-1000` at 20 % + 2px offset | `#FFFFFF` at 24 % |

**Status colours — the only hues in the system.** Deliberately desaturated so they read as information, not decoration, and **always** accompanied by an icon and a text label (never colour-only — WCAG 1.4.1 and the reality that these screens get printed and photographed).

| Status | Light fg / bg | Dark fg / bg |
|---|---|---|
| success | `#15803D` / `#F0FDF4` | `#4ADE80` / `#0F1F14` |
| warning | `#A16207` / `#FEFCE8` | `#FACC15` / `#1F1A08` |
| danger | `#B91C1C` / `#FEF2F2` | `#F87171` / `#1F1010` |
| info | `#374151` / `#F5F5F5` | `#D4D4D4` / `#171717` |

Note `info` is intentionally neutral — "under review" is the most common state in this product and does not deserve a colour.

**Rules**
- No gradients, no coloured cards, no coloured section headers, no brand tint behind content.
- One shadow for cards (`0 1px 2px rgb(0 0 0 / 0.04)`), one for overlays (`0 8px 24px rgb(0 0 0 / 0.12)`). Borders do the work, not shadows.
- Emphasis order: weight → size → spacing → border → fill. Colour is last and usually unnecessary.
- Dark mode tokens are defined now and wired via a `data-theme` attribute; the MVP ships light-first, with dark available because the token layer already supports it.
- The client's logo/wordmark is the only place brand colour may appear (assets still outstanding — NFR-6).

### Typography
Inter (system fallback: `-apple-system, Segoe UI, Roboto`), `font-feature-settings: "cv11", "ss01"` for the cleaner single-storey glyphs that suit a monochrome UI. Scale: `12 / 14 / 16 / 18 / 20 / 24 / 30 / 36`. Body 16 customer, 14 admin. Line height 1.5 body, 1.25 headings. Weights 400 / 500 / 600 only — in a colourless system, weight *is* the hierarchy, so use it deliberately. Tabular numerals for money, dates and counts. Headings are `-0.01em` tracked; nothing is ALL CAPS except 11px table-header labels at `0.04em`.

### Spacing & layout
4px base: `4 8 12 16 24 32 48 64`. Customer content max-width 1120px, admin 1600px fluid. Grid: 12 columns desktop, 4 mobile. Card padding 24 customer / 16 admin. Radius 8 (cards) / 6 (inputs, buttons). Shadow: one elevation for cards, one for overlays — no shadow zoo.

### Breakpoints
`sm 640 · md 768 · lg 1024 · xl 1280 · 2xl 1536`. Customer is mobile-first. Admin targets ≥1280 with a usable ≥768 fallback (tables become stacked cards below `md`).

### Icons
**AntD icons (`@ant-design/icons`)** — decided in M0, used by both apps, never mixed with another set. 20px inline, 16px in dense tables. Every icon-only button carries `aria-label`.

## 2. Components (build once, in `admin/src/components/ui` and `customer/src/components/ui`, same API)

| Component | Required states / notes |
|---|---|
| Button | primary · secondary · ghost · danger; loading (spinner + disabled) · disabled (with reason tooltip) |
| Input / Textarea / Select / DatePicker / FileUpload | label, hint, error, disabled, required marker; error text below, red border + icon |
| Form | inline field errors + a summary block above submit listing failing fields as anchors |
| Table | server pagination, sortable allowlisted columns, sticky header, row actions, loading skeleton, empty state, selected-rows bar |
| Card | header/body/footer; used for dashboard next-action items |
| Badge / StatusChip | one variant per domain status, mapped centrally (see §3), tooltip carries the date/actor |
| Alert / Banner | info · success · warning · danger; dismissible or persistent |
| Dialog / Modal | title, body, cancel + confirm; danger variant requires typed confirmation for terminate/cancel |
| Drawer | detail-without-navigation (admin quick view) |
| Tabs | deep-linkable via query param |
| Breadcrumbs | admin only, from route hierarchy |
| Stepper | application form (5 steps): completed · current · upcoming · error-on-step |
| Timeline | approval history, member status history, payment history |
| EmptyState | illustration/icon + one-sentence reason + the single action that resolves it |
| Skeleton | list, card and detail variants — never a bare spinner on a blank page |
| ErrorState | message + retry + "contact support" with the request id |
| Toast | success/error, 4s, action link ("View invoice") |
| FileList | name, size, type icon, verification chip, download, replace |
| MoneyText | currency + tabular figures + optional strikethrough for cancelled |
| PermissionGate | renders children only if permission present (UX only — backend still enforces) |

## 3. Status → visual mapping (single source of truth, shared constant file)

| Domain status | Variant | Label shown |
|---|---|---|
| Application DRAFT | neutral | Draft |
| SUBMITTED / UNDER_REVIEW | info | Under review |
| RETURNED_FOR_CORRECTION | warning | Action needed |
| APPROVED | success | Approved |
| REJECTED / WITHDRAWN | danger / neutral | Rejected / Withdrawn |
| Member PENDING | info | Awaiting payment |
| ACTIVE | success | Active |
| SUSPENDED | warning | Suspended |
| EXPIRED / TERMINATED | danger | Expired / Terminated |
| Invoice DRAFT / ISSUED | neutral / info | Draft / Unpaid |
| PARTIALLY_PAID | warning | Partly paid |
| PAID | success | Paid |
| OVERDUE | danger | Overdue |
| CANCELLED | neutral | Cancelled |
| Payment SUCCESS / FAILED / REFUNDED | success / danger / warning | Paid / Failed / Refunded |
| Document PENDING / VERIFIED / REJECTED | info / success / danger | Awaiting verification / Verified / Rejected |
| Event DRAFT / PUBLISHED / CANCELLED / COMPLETED | neutral / success / danger / neutral | — |

## 4. Copy rules

Sentence case everywhere. Buttons are verbs ("Submit application", not "Submit"). Dates as "12 Aug 2026" (+ relative "2 days ago" in queues). Money as "₹25,000.00". Never expose ids to members; admins see ids in a monospace chip.

## 5. Implementation

Tailwind for layout/spacing/typography + Ant Design 5 for complex widgets (table, date picker, drawer), themed via `ConfigProvider` from the same tokens — the Elvee approach, so muscle memory carries. AntD mapping: `colorPrimary = --n-1000`, `colorBorder = --n-200`, `colorBgContainer = --surface`, `colorText = --fg`, `colorTextSecondary = --fg-muted`, `borderRadius = 8`, `wireframe = false`, and AntD's default blue is overridden everywhere so no stray brand-blue leaks into links, switches or focus states. Tokens live in `tailwind.config.ts` + `theme/tokens.ts` and are the only place a colour literal may appear. Tokens are emitted as **RGB channel triplets** (`--n-0: 255 255 255`) rather than hex so Tailwind opacity modifiers work; hex exists only inside `tokens.ts`. AntD is wrapped with `@ant-design/cssinjs` `hashPriority="high"` so Tailwind preflight and AntD coexist. A raw hex outside the token file fails review.

## 5a. Admin theme source of truth

The admin chrome follows `theming-admin-black-white/` (SKILL.md, palette.md, layout.md, tables.md, components.md) at the repo root. Where that skill and this document disagree, **the skill wins for admin screens**; this file remains authoritative for the customer app.

Applied 2026-08-13:

| Role | Value | Note |
|---|---|---|
| Page canvas · sidebar | `#fafafa` | Sidebar is separated by a hairline, not a hue |
| Cards · header · table body | `#ffffff` | |
| Raised (table header, wells) | `#f5f5f5` | |
| Hover / selected fill | `#f0f0f0` / `#ececec` | Selected nav is a grey pill — no accent bar |
| Border | `#e5e5e5` | |
| Ink / muted / subtle | `#171717` / `#737373` / `#a3a3a3` | |
| CTA fill / hover | `#262626` / `#404040` | **Not `#0a0a0a`** — a large near-black surface is a visual trap in a light tool |
| Focus | `0 0 0 3px rgba(23,23,23,0.10)` + ink border | Never the browser blue |

> **Preflight trap.** Tailwind preflight is off so AntD's reset can own element defaults. Preflight is also what sets `border-width: 0` **and** `border-style: solid` on every element. Without the style, a `border-b` sets a width the browser never draws — every hairline in the app silently disappeared. Without the zeroed width, restoring the style makes every element sprout a UA border. `styles/index.css` sets both in `@layer base`; do not remove one half.

**Semantic pairs** (the only hues, and `info` is now blue rather than neutral): success `#1D7A4A`/`#EAF5EF` · warning `#9A6700`/`#FDF3E3` · danger `#C0392B`/`#FCEBE9` · info `#1A5E8A`/`#EBF4FB` · neutral `#525252`/`#F5F5F5`.

**Density:** body 13px · table header 11px uppercase `0.04em` · page title 18px · meta 12px. Controls 32px (28px in rows). Radius 8 for controls, 10 for containers, 999 for pills.

**The lining:** sidebar logo row and content header are both 56px and share one continuous hairline. Sidebar is a fixed 240px / 64px collapsed — never a percentage. Identity lives in the sidebar footer; the header answers "which page is this".

**Actions are icons, not words.** Row actions are 28px icon buttons, right-aligned, ink at rest and red only on hover for destructive ones, with the verb in a tooltip and `aria-label`. Two link-coloured words repeated down forty rows is a wall the eye has to skip to read the data.

**Create and edit happen in a side drawer, not a modal.** A modal covers the list the operator is working from, so every "what did that other row say?" costs a cancel and a re-open. The drawer keeps the table visible and pins its actions in a footer. Modals stay for confirmations — a destructive yes/no genuinely should block the screen.

**One title per screen.** The app header renders it; `PageHeader` keeps the `h1` visually hidden for the heading outline and screen readers, then renders subtitle and actions only. Card titles that restate the tab were removed.

## 5b. Admin chrome — patterns fixed in M1 (reference: Elvee admin)

The first admin build shipped a dark navy header. AntD's `Layout` defaults `headerBg` and `siderBg` to `#001529`, and a Tailwind class on the element loses to `.ant-layout-header` — so the fix belongs in the token layer, never in a specificity fight. `Layout` tokens are now set explicitly (white header, light body, neutral trigger).

| Pattern | Rule |
|---|---|
| Header | White surface, 56px, `0 24px` padding, hairline bottom border. Chrome recedes; content is the only thing with contrast |
| Page body | `--n-50`, not white — so white cards read as surfaces rather than dissolving into the page |
| Content gutter | 24px, full width. Admin tables need the horizontal room; no centred max-width column |
| `PageHeader` | Every screen starts with it: 24px/600 title, muted subtitle, right-aligned actions, hairline separator. One component so 36 screens cannot each invent a title treatment |
| Cards in a grid | `Card` is a flex column and its body is `flex-1 flex-col`, so a footer with `mt-auto` pins to the bottom. Action rows then align across cards of unequal height — staggered buttons are what make a grid read as broken |
| Alerts | Subtle tint + hairline, not AntD's saturated fill. In a monochrome system a filled block out-shouts the content it describes |
| Empty states | Never alongside a populated list. An empty state under six visible queues contradicts itself |

## 6. Definition of done for any screen

Tokens only (no ad-hoc colours/spacing, no raw hex) · all seven states handled · keyboard reachable with a visible focus ring · labels bound · AA contrast in **both** light and dark tokens · status conveyed by icon + label, not colour alone · responsive at 375 / 768 / 1280 (customer screens: contractual, FR-22) · passes the four-line rubric in `ux-principles.md` §2 — **answered by the interface, never by an explanatory panel on the screen**.
