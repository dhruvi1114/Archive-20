# Tables — headers, sort, filter, pagination

A data table is the main product surface of this admin. Theme, alignment, sort, filter, and pagination are one contract. Shipping a recolored table that still cannot sort or page is a failed pass.

Use Ant Design `Table`. Do not introduce a new grid library.

## Visual

Wrap in a white card: `1px #e5e5e5`, radius `10px`, overflow hidden. No extra outer drop shadow.

| Part | Spec |
| --- | --- |
| Header row | bg `#f5f5f5`, height `40px`, `11px` / 600 / uppercase / tracking `0.04em` / `#737373` |
| Header border | bottom `1px #e5e5e5` |
| Body cell | `13px` / `#171717`, padding `8px 12px`, height ~`44px` |
| Row border | bottom `1px #f0f0f0` |
| Row hover | `#fafafa` |
| Selected row | `#f5f5f5` |
| Frozen columns | same header/body colors; divider `1px #e5e5e5` |
| Numeric cells | `tabular-nums`, right-aligned |
| Dates | left-aligned, `12–13px`, `#525252` |
| Status | left-aligned pill (semantic colors from palette.md) |
| Actions | right-aligned, icon buttons `28px`, ink icons, tooltip |
| Empty | `py-10`, title `14px #171717`, hint `12px #737373` — tell them to clear filters if any are on |

`size="small"` or `middle`. Default Ant `large` is too tall.

Sticky header when body scrolls. `scroll.y` fills leftover viewport (`calc(100vh - shell - page chrome - toolbar - pagination)`). Prefer scrolling **inside** the table, not the whole page, on list routes.

Horizontal scroll when columns exceed width. Do not squash key columns below readable width. `ellipsis` + Tooltip on long names.

Do **not** center every cell (the current `.user-table` global center is a defect). Alignment:

- Text / IDs / names → left
- Numbers / money / weights → right
- Status / tags → left
- Checkbox select → center
- Row actions → right

Mono only for IDs/SKU/codes, `12–13px`.

## Sorting

Every comparable column is sortable: dates, numbers, money, names, statuses with a defined order.

```ts
{
  title: 'Date of order',
  dataIndex: 'dateOfOrder',
  sorter: true,          // server-driven lists
  // sorter: (a, b) => ... // client lists only
  sortDirections: ['ascend', 'descend'],
}
```

- Server lists: `sorter: true` + send `sortBy` / `sortOrder` on `onChange`. Do not pretend to sort one page locally.
- Client lists (already-loaded arrays): in-column compare. Handle `null` as last.
- Default sort: the column operators actually need (usually date desc or name asc). Show it as the active sort on first paint.
- Header must look sortable: Ant sort caret, muted `#a3a3a3`, active `#171717`. Do not hide the caret.
- One column sorted at a time unless the API already supports multi-sort.
- Sorting must not reset filters. Paging resets to page 1 on sort change.

Do not add sort on: action columns, image columns, free-form blobs.

## Filtering

Match the data. Do not ship a search box that only searches one of five useful fields and call it done.

### Always

- **Search** on list pages that have a name/id/email/SKU. Debounced 300ms, `width 320–360px`, prefix search icon, clear `allowClear`. Placeholder names the fields (`Search order ID, customer…`).
- Reset page to `1` on search/filter change.

### Column vs toolbar vs drawer

| Situation | Pattern |
| --- | --- |
| 1–3 enum columns (status, type) | Column `filters` + `onFilter`, or a compact Select in the toolbar |
| Date field | `RangePicker` in the toolbar, `disabledDate` future if records cannot be in the future |
| 4+ dimensions (status + vendor + store + date + …) | Toolbar: search + date + “Filters” button with Badge count; extra fields in a drawer; **applied chips** under the toolbar |
| Boolean (active/inactive) | Compact Select or column filter, not a whole drawer |

Applied chips: `{label}: {value}` with close. “Clear all” as `12px` ink link, not a red control.

Column filters: Ant `filters` / `filterSearch` for long enums. Filtered header state uses grey, not a colored highlight.

Do not duplicate the same filter in the column and the drawer unless they stay in sync.

### Filter UX

- Show result count in pagination (`1–50 of 432`) so the operator knows the filter worked.
- Empty + active filters → “No matches” + clear, not a blank table.
- Persist filters in URL search params on high-traffic lists (Orders, Inventory, Users) so back/refresh keeps them. Other lists: in-memory is enough.

## Pagination

Required on any list that can exceed one page. Do not use `pagination={false}` and then dump 500 rows.

Place **inside the table card**, bottom border-top, right-aligned (total text left of the pager is OK):

```
[ 1–50 of 432 orders          ‹  1  2  3  …  ›    50 / page ]
```

```tsx
<Pagination
  size="small"
  current={page}
  pageSize={pageSize}
  total={total}
  showSizeChanger
  showQuickJumper={total > 200}
  pageSizeOptions={['20', '50', '100']}
  showTotal={(total, range) => `${range[0]}–${range[1]} of ${total}`}
  onChange={onPageChange}
/>
```

| Spec | Value |
| --- | --- |
| Default page size | `50` (not 100 unless the row is tiny and the API already uses 100) |
| Options | 20 / 50 / 100. Add 200 only if the API is happy and rows are compact |
| Changing page size | Reset to page 1 |
| Chrome | Ink text, grey border, **selected page = `#262626` fill white text** (monochrome). No colored page number |
| Loading | Keep previous rows or table loading overlay; do not unmount pagination |

If the Table's built-in `pagination` prop is used, style it to this layout (`position: bottomRight`) rather than a second Pagination plus `pagination={false}` — one control, not two. Existing split (Table `pagination={false}` + sibling Pagination) is fine if both sit in the same card footer.

## Header content

Header titles are sentence- or title-case in the column `title` string, then CSS uppercase. Keep titles short (`Date`, `Status`, `Amount`). Units in the header (`g`, `ct`, `₹`) when every cell is that unit.

Sort + filter icons must fit without wrapping the label. Set `width` on columns. Fixed `left` on identity (checkbox + ID/name). Fixed `right` on actions.

## Row behavior

- If the row has a detail page, `onRow` click navigates; action buttons `stopPropagation`.
- Cursor `pointer` only when the row is clickable.
- Don't use colored left borders on rows for status — use the status pill. A 3px colored bar on every row is noise.

## Checklist per table

- [ ] Header `#f5f5f5`, 11px muted uppercase, 40px
- [ ] Alignment: text left, numbers right, actions right
- [ ] Sort on comparable columns; active sort visible
- [ ] Search and/or filters that match actual fields
- [ ] Chips or column-filter state visible when active
- [ ] Pagination with total, range, size changer
- [ ] Sticky header; body fills leftover height
- [ ] Empty state
- [ ] Semantic color only on status/delta cells
- [ ] No per-cell colored action links — ink text, underline on hover
