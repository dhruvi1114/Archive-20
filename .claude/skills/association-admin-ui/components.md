# Component catalogue

Everything here is exported from `@/components/ui`. Props listed are the ones that
carry a decision; the rest are pass-through to the Ant Design component underneath.

## DataTable

Wraps Ant Design's `Table`. Owns server pagination, server sort, and all four
states (loading / error / empty / populated), so a page never builds them.

| Prop | Why it exists |
|---|---|
| `pagination` | The `PaginationMeta` envelope from the API. **Total comes from the server, never `data.length`** — client pagination shows a wrong total the moment there is a page two. |
| `onPageChange` | `(page, limit)`. Changing page size returns to page 1; a deep page may not exist at the new size. |
| `unit` | Plural noun: "Showing 1–20 of 42 **members**". Anonymous otherwise on a screen with more than one list. |
| `serial` | Prepends "Sr.", counting from the page offset — position in the LIST, not the array. |
| `sort` / `onSortChange` | Server sort. A `sorter` function would reorder the twenty rows on screen and call it sorted — a lie you discover on page two. |
| `filtered` / `onClearFilter` | Swaps the empty state for "nothing matched" + Clear search. |
| `emptyTitle` / `emptyDescription` / `emptyAction` | The genuinely-empty state: what is missing, why, and the one thing that fixes it. |
| `summary` | Left half of the footer bar, for counts about the whole set. |

**Column conventions:**

```tsx
{ title: 'Code', dataIndex: 'code', width: 160,
  render: (v: string) => (
    <span className="font-mono text-supporting"><Highlight text={v} query={search} /></span>
  ) }
```

- **Column headers are Title Case** — every word capitalised: `Asked For`,
  `Effective From`, `Tier Code`. They are labels, not sentences. Everything else
  in the app stays sentence case, including the empty-state titles inside the
  same table ("No applications yet"), which *are* sentences.
- Every column takes a `width` **except one**, which absorbs the slack. Put it last before Actions.
- Actions: `title: 'Actions'`, `width: 80` (two icons) or `56` (one), `fixed: 'right' as const`.
- Codes are `font-mono text-supporting`. Numbers that stack down a column get `tabular`.
- Everything is left-aligned, numbers included.

## SearchInput

Toolbar search wired to a server-side filter.

Keeps its own text and hands the committed value up after 300ms; Enter commits
immediately. Controlled from outside, so a cleared filter or a tab switch moves
the box too. `className` sets the width — it goes on a wrapper, not the input
(see antd-traps.md).

```tsx
<SearchInput value={search} onChange={onSearch} label="Search categories"
  placeholder="Search code or name…" className="w-[240px]" />
```

`label` is the accessible name; there is no visible label in a toolbar.

## The four selects

They differ by **who owns the label**, not by what they do.

| | Renders its own label? | Where |
|---|---|---|
| `Select` | Yes — label, hint, error | A form field on its own |
| `FormSelect` | No | Inside a `Form.Item`, which draws the label |
| `InlineSelect` | No — `label` is the aria-label | Toolbars, pagination bars. Sized like a button |
| `MultiSelect` | No | Inside a `Form.Item`, for several values |

All four share one arrow: a Lucide `ChevronDown` that rotates 180° when open —
one mark turning over, not two swapped glyphs.

`FormSelect` and `MultiSelect` put the search box **inside the panel**, which
Ant Design's own `showSearch` will not do: that turns the closed control into a
text input, so the current value disappears the moment you open it. Pass
`searchThreshold={6}` on a genuinely fixed short list to hide the search box.

`MultiSelect` extras: tags collapse to `+n` (`maxTagCount="responsive"`), a
Select all row that flips to Deselect all, and a footer with the count and Clear
all. **Select all acts on what is visible** (a filtered list); **Clear all
ignores the filter**, because it says "all" about the selection, not the list.

## RowActions

Icon buttons for a row. 24px, matching the status chip so neither sets the row
height. Icons are Lucide at `size={16} strokeWidth={1.5}`, ink not coloured —
a destructive one turns red on hover only.

```tsx
<RowActions actions={[
  { key: 'edit', icon: <Pencil size={16} strokeWidth={1.5} />, label: 'Edit category',
    onClick: () => openEdit(row) },
  { key: 'delete', icon: <Trash2 size={16} strokeWidth={1.5} />, label: 'Delete category',
    danger: true, onClick: () => deletion.ask(row) },
]} />
```

`label` is the tooltip and the accessible name. Prefer **`disabled` +
`disabledReason` over `hidden`**: an empty Actions cell beside a live one reads
as a rendering fault, and gives no way to tell "you may not" from "there is
nothing to do".

## ConfirmDialog + useConfirm

```tsx
const deletion = useConfirm<Category>();
// in the row action: onClick: () => deletion.ask(row)

<ConfirmDialog
  open={deletion.target !== null}
  title={`Delete ${deletion.target?.name ?? 'category'}?`}
  description="Tiers, fees and members pointing at this keep pointing at it. If any do, the delete is refused — deactivate it instead."
  loading={deletion.busy}
  onCancel={deletion.cancel}
  onConfirm={() => deletion.confirm(remove)}
/>
```

`useConfirm` holds the pending record and the in-flight flag. Without it each
screen keeps its own pair and they drift — one forgets to clear on error and
leaves a dialog that cannot be shut; one forgets `busy` and a double-click sends
the delete twice.

Dialogs are centred app-wide. The description says what happens to records that
point at this one — not a restatement of the title.

## Cell components

| Component | Use for | Notes |
|---|---|---|
| `TextCell` | Free text — descriptions, notes, names | One line, full value on hover. `width` = column width less 24px of padding |
| `DateCell` | Any date | Date in the cell, full timestamp on hover, `tabular` digits |
| `MoneyText` | Amounts | |
| `StatusChip` | A state | Always icon + label; colour alone fails WCAG 1.4.1 |
| `TagList` | Several values | First `max` as chips, rest behind `+n` with a hover card |
| `NotAvailable` | Nothing to show | `label` overrides "N/A" — "Not issued", "None uploaded" |
| `Highlight` | A search match | Colour only, no padding or weight — those move the surrounding letters |
| `Badge` | A count or qualifier | "3 to verify", "Overdue", "New". `tone` for meaning, `tooltip` when it abbreviates |
| `StackedCell` | A value plus its context | Legal name under trading name, application number under applicant. Both lines truncate |

**`Badge` vs `StatusChip`:** `StatusChip` is a record's STATE — it resolves a
backend enum through the status table and always carries an icon, because status
must never be colour alone. `Badge` is everything else a cell needs to say: a
count, a qualifier, a marker with no enum behind it. It has no icon, deliberately
— a second icon beside a StatusChip in one cell reads as a second status.

`TextCell` clips with a `max-width`, not the column's `ellipsis` prop, which
cannot work on these tables (see antd-traps.md).

## Page furniture

**`PageHeader`** — `title` (visually hidden; the app header already shows it),
optional `subtitle`, `actions` (search then create button), `filters`. 8px below
each row: the controls and the table are one object, tighter than the 12px page
frame.

**`Card flush`** — the surface around a table. `flush` removes body padding
**and turns on clipping**, so the table's square corners don't sit over the
card's radius. Clipping is off for padded cards: a focus ring is a 3px
`box-shadow` and would be cut off.

**`Tabs variant="pill"`** — tabs over one dataset (Categories / Tiers). Deep-links
via `?tab=`. Renders **only the active pane**, which is what lets a tab body hand
its create button and search box up to the tab row via `actions`.

**`FormDrawer`** — create/edit. `title`, `confirmLabel`, `loading`, `onCancel`,
`onConfirm`.

**`FieldLabel`** — a label with a `?` that reveals a one-line rule on hover and
focus. For rules needed *once* (a code's character set, an irreversible choice),
not for guidance needed every time.

**`FilterDropdown` / `FilterGroup`** — every filter on a list page, behind one
button with a count badge. It holds two copies of the state: `value` is what the
list shows, `draft` is what the user is editing, and nothing reaches the list
until Apply. That is the whole point — a three-filter panel costs one request
instead of three, and a half-finished combination never hits the server.

Clear and Apply are deliberately asymmetric: Apply commits and closes, Clear
commits and stays open, because "clear" is usually the first half of "clear, then
pick something else".

Wrap each filter in `FilterGroup label="…"`, and use `FormSelect` inside it (the
panel supplies the label, so the control must not).

```tsx
<FilterDropdown<MemberFilters>
  value={filters} emptyValue={EMPTY_MEMBER_FILTERS}
  onApply={applyFilters} onClear={clearFilters} activeCount={activeFilterCount}
>
  {(draft, setDraft) => (
    <FilterGroup label="Status">
      <FormSelect value={draft.status} options={…}
        onChange={(next) => setDraft((d) => ({ ...d, status: next }))} />
    </FilterGroup>
  )}
</FilterDropdown>
```

**`PermissionGate`** — wraps anything that needs a permission. Pages should not
be reading `can()` inline to decide whether to render a control.

**`Alert`**, **`toast`** — `Alert` for an error that belongs beside the thing it
is about; `toast` for the outcome of an action that has already finished.
