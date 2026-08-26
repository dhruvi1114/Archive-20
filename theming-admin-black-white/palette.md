# Palette — subtle black-white + universal meaning

Light-first. Cool greys. Near-black ink. Color only when the user must read meaning at a glance.

## Surfaces and chrome (monochrome)

| Role | Token to drive | Value | Use |
| --- | --- | --- | --- |
| Page canvas | `--bg-page` | `#fafafa` | App background behind cards |
| Sidebar | `--sidebar-bg` | `#fafafa` | Distinct from main by border, not by hue |
| Main / cards | `--bg-card` | `#ffffff` | Content, table body, drawers, modals |
| Raised / header fill / table header | `--surface-raised` | `#f5f5f5` | Table thead, grouped rows, inset wells |
| Hover fill | `--surface-hover` | `#f0f0f0` | Nav hover, row hover (or `#fafafa` on white rows) |
| Selected fill | `--surface-selected` | `#ececec` | Selected nav, selected table row |
| Border | `--border` / `--line` | `#e5e5e5` | Default hairline |
| Border strong | `--border-strong` | `#d4d4d4` | Inputs at rest, splitters |
| Text primary | `--ink` | `#171717` | Body, titles, icons on light |
| Text muted | `--ink-muted` | `#737373` | Meta, placeholders, section labels |
| Text subtle | `--ink-subtle` | `#a3a3a3` | Disabled, timestamps secondary |
| Inverse text | `--text_w` | `#ffffff` | Label on primary CTA only |
| CTA fill | `--cta` | `#262626` | Primary buttons, active solid controls |
| CTA hover | `--cta-hover` | `#404040` | Primary hover — lighter, still not grey-mud |
| CTA disabled | `--cta-disabled` | `#d4d4d4` | Disabled fill; label `#a3a3a3` |
| Focus ring | | `0 0 0 3px rgba(23,23,23,0.10)` plus `1px #171717` border | Inputs, buttons |
| Shadow | `--shadow` | `0 1px 2px rgba(0,0,0,0.04)` | Cards optional; prefer border over shadow |
| Shadow raised | `--shadow-lg` | `0 8px 24px rgba(0,0,0,0.08)` | Dropdowns, popovers, drawers |

### Pitch-black rule

| Allowed | Forbidden |
| --- | --- |
| `#171717` body text | `#000000` page, sidebar, header, table header, modal mask-adjacent panels |
| `#262626` primary button fill | `#000000` or `#0a0a0a` as a large panel / hero / footer |
| `#0a0a0a` only if a CTA on `#fafafa` fails contrast and `#262626` is not enough | Black overlays, black selected-nav, black table headers |

If you need more contrast, darken **text** one step. Do not darken the room.

### Map existing tokens by role

After analysis, assign current **names** to the roles above. Typical names in this app (`primary`, `secondary`, `muted`, `line`, sidebar vars, Ant `colorPrimary`, and any other existing color keys) keep their names. Only values change.

- Tokens used as CTA / selected / link → `--cta` / `--ink`
- Tokens used as page or card background → `#fafafa` / `#ffffff`
- Tokens used as borders → `#e5e5e5`
- Tokens used as muted text → `#737373`
- RGB companion vars (`--*-rgb`) must match the new hex so `rgba(var(--*-rgb), a)` stays grey, not tinted

Shadows that currently use a tinted rgba become `rgba(0,0,0,.04)` / `rgba(0,0,0,.08)`.

## Decision: color or not?

```
Is this chrome (nav, button, input, border, tab, focus, card, header, pagination)?
  → Monochrome. Always.

Is this meaning the operator must spot in a list or chart?
  (status, pass/fail, pending/complete, delta up/down, chart series, QC, payment state)
  → Universal semantic color below.

Is this a logo, photo, or third-party brand mark?
  → Leave as-is.
```

When unsure, chrome.

## Universal semantic colors

Muted, not neon. Soft background + darker text. Never use these on sidebar, header, primary buttons, or table chrome.

| Meaning | Text | Background | Border (optional) |
| --- | --- | --- | --- |
| Success / complete / pass / delivered / up | `#1D7A4A` | `#EAF5EF` | `#C6E6D3` |
| Warning / pending / overdue / amber | `#9A6700` | `#FDF3E3` | `#F0D9A8` |
| Danger / fail / reject / down | `#C0392B` | `#FCEBE9` | `#F0C4BE` |
| Info / in-progress / assigned | `#1A5E8A` | `#EBF4FB` | `#C5DDF0` |
| Neutral / unknown / manufacturing | `#525252` | `#F5F5F5` | `#E5E5E5` |

Use the same pairs for Ant `colorSuccess` / `colorWarning` / `colorError` / `colorInfo` so Tags, Badges, Alerts, and Notifications match lists.

KPI deltas: up = success text, down = danger text, neutral = muted ink. Card chrome stays white/grey.

Progress bars: track `#f0f0f0`; fill uses the semantic color of the state (QC complete = success; in-progress = info). Do not fill with CTA black unless the bar is purely decorative.

## Charts

Chart **chrome** is monochrome. Chart **series** may use color.

| Part | Value |
| --- | --- |
| Plot background | transparent / `#ffffff` |
| Grid lines | `#f0f0f0` |
| Axis line | `#e5e5e5` |
| Axis / legend label | `#737373`, 11px |
| Tooltip | `#ffffff` bg, `#e5e5e5` border, `#171717` text, radius 8, light shadow |
| Empty / no-data | muted text, no colored illustration required |

**Series**

- Semantic data (rising / falling / pass / fail): use the universal pairs (solid hex of the **text** column, e.g. rising `#1D7A4A`).
- Non-semantic categories (3 or fewer): `#262626`, `#737373`, `#a3a3a3`.
- Non-semantic categories (4+): add `#1A5E8A`, `#1D7A4A`, `#9A6700`, `#7C3AED` in that order. Stop adding hues. Recycle with opacity before inventing a rainbow.
- Do not use a 12-stop categorical rainbow. Do not use brand-tinted golds.

Sparklines: one stroke `#262626` at 1.5px unless the sparkline encodes a status (then semantic).

Maps: greyscale base; data choropleth uses a grey ramp (`#f5f5f5` → `#262626`) unless regions encode a status.

## Ant Design tokens (target)

```js
{
  colorPrimary: '#262626',
  colorPrimaryHover: '#404040',
  colorPrimaryActive: '#171717',
  colorPrimaryBg: '#f5f5f5',
  colorText: '#171717',
  colorTextSecondary: '#737373',
  colorBgBase: '#fafafa',
  colorBgContainer: '#ffffff',
  colorBorder: '#e5e5e5',
  colorBorderSecondary: '#f0f0f0',
  colorLink: '#171717',
  colorLinkHover: '#404040',
  colorSuccess: '#1D7A4A',
  colorWarning: '#9A6700',
  colorError: '#C0392B',
  colorInfo: '#1A5E8A',
  colorBgElevated: '#ffffff',
  borderRadius: 8,
  fontFamily: 'Avenir LT Pro, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica Neue, Arial, sans-serif',
  controlOutline: 'rgba(23,23,23,0.10)',
}
```

`colorPrimary` is near-black so every Ant primary control follows chrome rules without per-button overrides.

## Tailwind color remap (keep names)

Point existing keys at the roles above. Do not add a parallel `ink` / `surface` scale unless a name is missing. Status keys already in `tailwind.config.js` (`status-green`, `status-red`, `status-amber-*`) stay semantic — retune them to the universal pairs if they drift.

## Hardcoded sweep

After tokens, remaining `#hex` in JSX/CSS:

1. Chrome hex → CSS var or Tailwind token
2. Semantic hex → universal pair (same meaning, consistent values)
3. One-off decoration hex → grey

Do not leave per-page `style={{ background: '…' }}` on buttons. Primary = `type="primary"` and the ConfigProvider token.
