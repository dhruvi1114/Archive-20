---
name: association-admin-ui
description: Use when building or changing any screen in the ILGDA association admin app (admin/) — a list page, a table, a form drawer, a filter or search bar, a confirmation, an empty state, a status chip, a date or money cell — or when a screen looks inconsistent with the rest of the app, or when reaching for an Ant Design component directly.
---

# Association admin UI

Every screen in `admin/` is assembled from shared components in `@/components/ui`. A page decides **what data it shows**; the components decide **how anything looks**. A page that styles its own control has created a second version of that control, and the two will drift.

**Reference implementation:** `admin/src/pages/masters/Categories.tsx`. Whatever you are building, that page has probably already solved it — read it before inventing anything.

## The rule

**If `@/components/ui` has it, a page must not import it from `antd`.** If the thing you need is not there, add it there, then use it.

What a page may still take from `antd`: `Form` / `Form.Item`, `Input` and `Input.TextArea`, `Switch`, `DatePicker`, `Segmented`, `Tooltip` — primitives with no wrapper yet. What it may **never** take: `Table`, `Select`, `Button`, `Modal`, `InputNumber`, `Checkbox.Group`, `Pagination`. Each of those has a wrapper that owns behaviour the raw component does not.

*Known exception, not a precedent:* `pages/applications/DecisionDialog.tsx` still uses a raw `AntSelect`. It predates `FormSelect`. Move it when you next touch that file.

Two consequences, both non-negotiable:

- **No page sets a colour, radius, height or font-size.** Those live in `admin/src/theme/tokens.ts` (values), `antdTheme.ts` (Ant Design component tokens) and `styles/index.css` (only what Ant Design has no token for). A hex code or a `text-[13px]` in a page is a bug.
- **No page hand-rolls behaviour a component already owns** — debounced search, pagination, confirm-before-delete, empty states, truncation. Four screens each had their own debounce before `SearchInput`, and they had already drifted.

## What to use for what

| You need | Use | Not |
|---|---|---|
| A list of records | `DataTable` | `antd` `Table` |
| Search over that list | `SearchInput` | `antd` `Input` + your own debounce |
| A filter in a toolbar | `InlineSelect` | `antd` `Select` |
| A select inside `Form.Item` | `FormSelect` | native `<select>` |
| A select with a visible label | `Select` | `Form.Item` + `FormSelect` |
| Several values in one field | `MultiSelect` | `Checkbox.Group` |
| A number field | `NumberInput` | `antd` `InputNumber` |
| The page's create action | `Button variant="primary"` | a bare `antd` `Button` |
| Row actions (edit/delete) | `RowActions` | icon buttons in a cell |
| Confirm a delete | `ConfirmDialog` + `useConfirm` | `window.confirm`, or deleting on click |
| A create/edit form | `FormDrawer` | `Modal` |
| The page's title row | `PageHeader` | an `<h1>` |
| Tabs over one dataset | `Tabs variant="pill"` | `antd` `Tabs` |
| A surface around a table | `Card flush` | a `div` with a border |
| Free text in a cell | `TextCell` | raw text |
| A date in a cell | `DateCell` | `formatDate` inline |
| Money in a cell | `MoneyText` | `toFixed` |
| A status | `StatusChip` | a coloured `span` |
| A count or qualifier pill | `Badge` | a `rounded-full bg-status-*` span |
| Two facts in one cell | `StackedCell` | a hand-built two-line `div` |
| Several tags in a cell | `TagList` | a joined string |
| Nothing to show | `NotAvailable` | `—`, `"None"`, or blank |
| Marking a search match | `Highlight` | `<b>` |

Full prop-level detail: [components.md](components.md).

## Building a list page

Follow `Categories.tsx`. The shape is always:

```
PageHeader                       ← one row: subtitle left, actions right
  actions: <SearchInput /> then <Button variant="primary">Add X</Button>
└── Card flush                   ← clips the table's corners
    └── DataTable                ← owns pagination, empty, loading, error
```

### Toolbar layout

**One row, actions right.** `PageHeader` lays its bar out `justify-between`:
explanatory text on the left, controls on the right, pushed to the edge. A page
never adds a second row of controls and never left-aligns the create button.

**Order within the actions group: search first, then the create button, last.**
Reading left to right that is narrow-the-list → add-to-the-list, and the primary
action sits at the end of the row where the eye stops.

**Search always goes in `actions`, whatever else the page has.** It is on every
list screen, and a control that moves between the left and right edge depending
on which page you are on is the single most visible inconsistency a list can
have.

**Filters go behind one `FilterDropdown` button, also in `actions`** — never as
a row of selects. Three selects across a row is three requests as the user works
through them, three chances to fire a half-finished combination at the server,
and a toolbar that outgrows the width of a laptop. The panel stages a draft and
commits it on Apply: one request, whatever the user changed.

**Filters are `MultiSelect`, not `FormSelect`.** "Submitted OR under review" is a
real question and a single-value filter cannot ask it. Two consequences: the
query param is a comma-separated list (`?status=SUBMITTED,UNDER_REVIEW`), and the
API must match with `ANY(...)` — see the `csv()` helper in the modules'
`*.types.ts`. **No "Any status" option:** an empty selection already means any,
and an option that means the same as choosing nothing is a third state to
explain.

*Watch the dependency array.* A filter read as an array is rebuilt on every
render, so `load` must depend on the raw param string, not the array, or it
refetches forever.

`PageHeader` still has a left-aligned `filters` slot for a control that must stay
visible rather than sit behind a button. Nothing uses it today. Reach for it only
when a filter is the point of the screen, not merely available on it.

**A choice between two LISTS is a tab, not a filter.** "My queue" vs "All
applications" changes which set you are looking at; status and stage narrow
whichever set that is. Tabs also keep the most consequential choice on the screen
visible, where the filter panel would hide it behind a button. Use
`Tabs variant="pill"` with its own `queryParam` (`scope`), and render the same
table as both tabs' children — see `ApplicationQueue.tsx`.

**On a tabbed page, tabs and controls share ONE line.** `Tabs variant="pill"`
takes an `actions` slot and lays that row out tabs-left / actions-right — so
hand the search box, the filter button and the create button to `Tabs`, not to
`PageHeader`. A tabbed page with its controls in `PageHeader` gets two rows where
one would do, and the tabs end up further from the table than the toolbar is.

Where the controls live depends on which component owns them: a tab body hands
its own create action up (`Categories.tsx`), a page that owns the whole list
passes them straight in (`ApplicationQueue.tsx`).

**8px below the row, then the table.** Both `PageHeader` and `Tabs` set it. The
controls and the list are one object, tighter than the 12px page frame around
the pair.

Non-obvious requirements, all learned the hard way:

1. **Search is server-side.** Pass `search` to the service; never filter the fetched page. A client filter cannot see rows on pages nobody has fetched.
2. **A new query resets to page 1.** Otherwise the filter cuts the list to six rows while you sit on page four, and the empty table reads as "no matches".
3. **Highlight the fields the server matched on** — and only those. `<Highlight text={v} query={search} />`.
4. **Pass `filtered` and `onClearFilter`** so the empty state says "nothing matched" rather than "nothing exists". Two different situations, two different next steps.
5. **`serial` and `unit`** on every table: `unit="categories"` makes the footer read "Showing 1–20 of 42 categories".
6. **Actions column:** `title: 'Actions'`, `width: 80`, `fixed: 'right' as const`.
7. **One column carries no `width`** — it absorbs the slack. Make it the last one before Actions (Status, usually), never the name column, or the name stretches and pushes everything else off-screen.
8. **Delete asks first.** `useConfirm<T>()` + `<ConfirmDialog>`; the description says what the delete will do to records pointing at this one.

## Building a form drawer

`FormDrawer` + `antd` `Form layout="vertical" requiredMark={false}`. Field layout:

- **Pairs share a row:** `<div className="flex gap-4">` with `className="min-w-0 flex-1"` on each `Form.Item`. Use `grid grid-cols-2 gap-4` when the two must stay equal regardless of content.
- **Free text takes the full width** on its own row.
- **Name leads, write-once code follows it.** The name is what the admin has in mind; the code is a consequence of it.
- **Write-once fields stay visible on edit, `disabled`** — never removed. The code is how the row is referred to everywhere else, and a form that hides it leaves you checking you opened the right record by its name alone. Swap the help text to say why it is fixed.
- **Rules go too:** `rules={editing ? [] : [...]}`, or validation fires on a field nobody can change.
- **One-line rules that a first-timer needs once** go in `FieldLabel help=` (a `?` beside the label), not in standing text under the field. Guidance needed *every* time stays visible.

## Capitalisation

**Labels are Title Case; sentences are sentence case.**

Title Case — every word capitalised — for anything that names a thing: nav
items, page titles, column headers, tab labels, field labels. `Categories &
Tiers`, `Fee Structures`, `Asked For`, `Effective From`.

Sentence case for anything that reads as a sentence: empty-state titles ("No
applications yet"), descriptions, help text, toasts, confirm-dialog bodies.

Page titles come from the nav label — `AppShell` derives the header's `h1` from
`NAV_GROUPS`, so a page's own `PageHeader title` must match its nav entry
exactly or the sidebar and the header will disagree.

## Type, spacing, colour

Never a raw size. The roles are `text-title-primary` (24/600), `text-title-secondary` (16/600), `text-supporting` (14/400 — tables, forms, buttons, most things), then the numeric scale `text-11`…`text-30` for the rest.

Spacing: 8px between a control row and the thing it controls (they are one object); 12px is the page frame. Table cells are 8/12 via tokens.

Colour is greyscale. The only hues are `StatusChip` states and the yellow search `highlight`. Surfaces run `surface` → `surface-subtle` → `raised` → `sunken`, with `zebra` for table banding.

## Ant Design traps

Ant Design routes several props somewhere other than where they appear to go. Three cost hours each on this app. Read [antd-traps.md](antd-traps.md) before debugging "my style isn't applying".

## Red flags

- `from 'antd'` in a page for anything but `Form` / `Input.TextArea`
- A hex colour, `rounded-[10px]`, or `text-[13px]` in a page
- `window.confirm`, or a delete that fires on click
- A `<select>`, or a checkbox group with more than four options
- An empty cell, an em-dash, or the word "None"
- `.filter()` over fetched rows to implement search
- A second component that does what one in `@/components/ui` already does — extend that one instead
