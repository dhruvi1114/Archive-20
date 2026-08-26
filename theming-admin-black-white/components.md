# Components — Ant Design and shared UI

Tokens in ConfigProvider are the base. `src/styles/ants.css` still has per-component overrides that will fight the theme (tinted table headers, tinted primary buttons, tinted sidebar selected, green collapse headers). Those overrides must follow this file or be deleted.

Do not leave one-off `className="!bg-[#…]"` on buttons after the token is retargeted.

## Buttons

| Type | Rest | Hover | Disabled |
| --- | --- | --- | --- |
| Primary | fill `#262626`, text `#fff`, border same | fill `#404040` | fill `#d4d4d4`, text `#a3a3a3` |
| Default | fill `#fff`, text `#171717`, border `#e5e5e5` | bg `#fafafa`, border `#d4d4d4` | text `#a3a3a3` |
| Text / link | no border, text `#171717` | bg `#f0f0f0` | `#a3a3a3` |
| Danger | semantic danger fill/text — this is meaning | darker danger | muted |

Radius `8px`. Height `32px` default, `28px` `small` in table rows. Primary is used **once per toolbar** (the main action). Everything else is default or text.

Do not color default-button hover with a leftover accent. Hover stays grey.

## Inputs, Select, DatePicker, InputNumber

- Height `32px`, radius `8px`, bg white, border `#e5e5e5`
- Placeholder `#a3a3a3`
- Hover border `#d4d4d4`
- Focus: border `#171717` + `box-shadow: 0 0 0 3px rgba(23,23,23,0.10)` — **never** a tinted ring
- Error: danger border + ring `rgba(192,57,43,0.12)` (meaning)
- Prefix/suffix icons `#737373`

Search inputs in toolbars: same spec, `allowClear`.

## Checkbox, Radio, Switch

- Unchecked border `#d4d4d4`
- Checked fill `#262626`, check/dot white
- Hover: border `#171717`
- Switch checked: `#262626` track (not green, unless the switch **is** a success state — rare). Most admin switches mean on/off, which is chrome → near-black.

## Tags, Badges, Status pills

- **Semantic status** → universal pairs in palette.md (pill, `12px`, `padding 2px 8px`, font-weight 500)
- **Neutral tags** (count, category): `#f5f5f5` / `#525252` / border `#e5e5e5`
- Badge count on the Filters button: `#262626` (chrome), not a colored accent
- BETA / MOCK / environment chips: semantic (info / warning)

Do not use `ant-tag` default candy colors for chrome labels.

## Tabs

- Ink bar: `2px #171717`
- Active text `#171717` / 600
- Inactive `#737373`
- Hover `#171717`
- Bottom border of the nav `#e5e5e5`
- No tinted background on the active tab
- Compact: tab padding `10px 4px`, nav margin-bottom `12px` (not 24px)

## Menu / Sidebar

See [layout.md](layout.md). CSS that currently sets selected to a tinted fill + left accent bar must be rewritten to grey pill. Popup (collapsed hover): white, `1px #e5e5e5`, radius `10px`, shadow `--shadow-lg`, item hover `#f5f5f5`, selected `#ececec` / `#171717`.

## Cards, Modals, Drawers, Popovers, Dropdowns

- White, `1px #e5e5e5`, radius `10px`
- Shadow only on floating layers (`--shadow-lg`), not on in-page cards
- Drawer header: `h-56px` equivalent, hairline bottom, title `14px` 600, close icon ink
- Drawer footer: hairline top, `padding 12px 16px`, secondary left/cancel, primary right
- Modal mask: `rgba(23,23,23,0.35)` — dim, not a black wall

## Table

See [tables.md](tables.md). Kill overrides that force cream/pink thead, ivory row hover, or centered `.user-table` cells.

Pagination item selected = `#262626` / white. Hover = `#f5f5f5`.

## Collapse

Header bg `#f5f5f5` (not green). Text `#171717`. Expand icon `#737373`.

## Upload / picture card

Border `#e5e5e5` dashed, hover border `#171717`. List on white.

## Notifications / Messages / Alerts

Use Ant semantic colors (success/warning/error/info). Icons + left border in the semantic color; background the soft pair. Text `#171717`. This is meaning.

## Typography / Headings

Shared `Heading` component: `18px` 600 `#171717`, no colored underline. Page subtitle `12px #737373` immediately under, `margin-top 4px`.

## KPI cards

White, hairline, radius `10px`, padding `12px 14px`. Label uppercase `11px #737373`. Value `20–24px` 600 `#171717` tabular. Delta uses semantic text color only. Icon well: `#f5f5f5`, ink icon, `32px`, radius `8px` — not a tinted square.

## Progress

Track `#f0f0f0`. Fill = semantic if the bar encodes a state; otherwise `#262626`. Height `6px`, radius full.

## Links inside tables

Ink `#171717`, hover underline. Do not use leftover accent hex on “View” / IDs.

## Icons

`currentColor`. Inactive nav `#737373`. Active nav `#171717`. Table actions `#525252`, hover `#171717`. Size `16px` default, `14px` in cells.

## Scrollbars

`6px`, thumb `#d4d4d4`, hover `#a3a3a3`, track transparent. No dark chunky thumbs.

## Focus (a11y)

Every interactive control: visible focus. Near-black ring. Do not `outline: none` without a replacement. Do not restyle focus to the browser’s default blue.

## Global CSS to treat as bugs when they fight the theme

In `src/styles/ants.css` / `index.css`:

- `.ant-btn-primary` hardcoded to an old accent
- `.ant-table-thead` cream/pink background
- `.ant-menu-item-selected` tinted fill + colored left border
- `.ant-collapse-header` green background
- Input focus rings that still use a tinted RGB variable instead of `rgba(23,23,23,0.10)`
- `.ant-radio-checked` fill using an old accent
- Sidebar compact selected still pointing at a colored icon

Replace with the values in this file. If an override only exists to copy the old look, delete it and let ConfigProvider win.

## Implementation order for a component pass

1. ConfigProvider tokens
2. Global ants.css overrides (table, button, menu, input focus, collapse)
3. Sidebar1 + Header + layout shell
4. Shared: KpiCard, DataTable, Heading, status helpers (`getStatusClassName`, etc.)
5. Page-level hardcoded button/tag/badge hex
6. Charts (chrome grey, series semantic/categorical per palette.md)

Status helper functions that return class strings should return the universal pairs, not a new one-off hex per screen.
