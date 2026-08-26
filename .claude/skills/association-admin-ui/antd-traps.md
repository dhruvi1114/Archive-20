# Ant Design traps

Places where Ant Design routes a prop somewhere other than where it appears to
go. Each of these presented as "my style isn't applying" and each took real time
to find. Check here first.

## 1. Size-suffixed tokens

**The trap:** Ant Design reads the **size-suffixed** component token for any
component rendering at a size other than the default. Setting the unsuffixed one
is silently ignored.

`DataTable` renders `size="middle"`, so:

```ts
Table: {
  cellPaddingBlock: 8,      // ← ignored
  cellPaddingBlockMD: 8,    // ← the one that applies
  cellFontSize: 14,         // ← ignored
  cellFontSizeMD: 14,       // ← the one that applies
}
```

Same for `size="small"` controls, which use the `SM` suffix:

```ts
Select: {
  borderRadius: radius.md,   // ← ignored by an InlineSelect
  borderRadiusSM: radius.md, // ← the one that applies
  controlHeightSM: 28,
}
```

**Symptom:** rows the wrong height, text the wrong size, a dropdown with 4px
corners next to 8px buttons.

## 2. `className` on an Input with a prefix

**The trap:** when an `Input` has a `prefix` or `suffix`, Ant Design wraps the
real `<input>` in an affix wrapper and sends `className` to the **inner** input.
A width set on the component lands on an element already inside a full-width box.

**Symptom:** the field stretches to fill its container and pushes whatever sits
beside it onto the next line.

**Fix:** put the width on a wrapper element. `SearchInput` already does this —
its `className` goes on a `div`.

## 3. `ellipsis` does not truncate on these tables

**The trap:** rc-table falls back to `table-layout: auto` whenever a table has
fixed columns **and** `scroll.x` is `max-content`. Both are true for every table
here — the first for the frozen Actions column, the second so columns size to
their content. Under `auto`, a column's `width` is only a **minimum**.

**Symptom:** a long description widens its column instead of being clipped by
it, pushing the columns after it off the end of the table.

**Fix:** clip with a `max-width` on the cell's own span. `TextCell` does this;
pass `width` as the column width less 24px of cell padding.

## 4. Tailwind vs Ant Design at equal specificity

**The trap:** Ant Design is emitted at single-class specificity and injected into
`<head>` at runtime. A single Tailwind utility on an Ant Design component is a
coin toss decided by injection order.

**Fix, in order of preference:**

1. A component token in `antdTheme.ts` — travels with the theme, flips with dark mode.
2. A two-class selector in `styles/index.css` (`.auth-scope .ant-btn`, `.data-table .ant-table-body`) — for what has no token: font weight, text-transform, layout of Ant Design's internal elements.
3. An inline `style` — last resort, for a single value that must win regardless (`NumberInput` sets its width this way, because `.ant-input-number` ships a fixed 90px).

Never `!important` in a page.

## 5. Styling Ant Design's internals needs a scoping class

Rules that target `.ant-table-body`, `.ant-table-container`, `.ant-select-arrow`
and so on cannot live in the component — our components never render those
elements, Ant Design does. Put a class on our component (`data-table`,
`auth-scope`, `segmented-tabs`) and scope the CSS to it, so the rule cannot
reach a future table that should not have it.

## 6. `scroll.y` is a max-height, not a height

**The trap:** passing `scroll={{ y }}` caps the body's height; it does not fill
it. With three rows in a tall card the body stops under the last row, and the
horizontal scrollbar drawn on its bottom edge floats mid-card.

**Fix:** `.data-table` stretches the wrapper chain and lets `.ant-table-body`
flex, so the body fills the card and its scrollbar sits above the pagination bar.
The stretch of the inner `<table>` is scoped with
`:has(.ant-table-placeholder)` — applied unconditionally it makes a single real
row a full card tall.

## 7. Measuring a table that starts as a skeleton

**The trap:** the first render of a list is the loading skeleton, which returns
before the table's box exists. A `useEffect(..., [])` measuring a ref runs once
against `null`, gives up, and never fires again once the rows arrive.

**Fix:** a **callback ref**, which runs when the node itself appears, whichever
render that turns out to be.

## 8. `darkAlgorithm` derives its own primary palette

**The trap:** Ant Design's dark algorithm generates a ramp from `colorPrimary`
rather than using it directly. Derivation from white can only go *downwards*, so
a white primary renders as mid-grey — a primary button indistinguishable from a
disabled one.

**Fix:** restate `colorPrimary`, `colorPrimaryHover` and `colorPrimaryActive` in
the component's own token block, which overrides the derived ramp. Also set
`colorTextLightSolid` — the label on a filled button — or it stays white on a
white button.

## 9. Ant Design adds its own `title` tooltips

`Segmented` and column `ellipsis` derive a `title` attribute from a string
label, giving you the browser's grey tooltip alongside — or instead of — yours.
Pass `title: ''` on the option, or `ellipsis: { showTitle: false }`.
