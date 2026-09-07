# Dashboard — design spec

**Date:** 2026-09-02 · **Module:** M10 · **Status:** approved, building
**Models:** the Dribee dashboard suite (`Distrix_Project/dribee-*`), studied 2026-09-02.

---

## 1. What it is

One dashboard, not a suite. Dribee has five (overview, sales, inventory,
procurement, finance) because it serves five departments; an association office
is one room. What is adopted is Dribee's **contract** and its **speed pattern**,
not its five-tab shape.

## 2. Layout, top to bottom

```
Filter bar        Period · Compare to
KPI row           Active Members · Overdue Invoices · Collected · Open Applications · Next Event
Work queue        the six permission-scoped cards (already built)
Charts            Membership Trend · Revenue Overview · Top Members
Upcoming Events
```

## 3. Decisions taken (2026-09-02, user)

| Question | Decision |
|---|---|
| KPI tiles | The five in the mockup, unchanged |
| Filters | **Period only.** No category filter — Dribee's third filter is a warehouse, and nothing here plays that role |
| Sparklines under each KPI | **Dropped.** Plain figures, as Dribee has them. A sparkline needs its own 12-point series per tile, and it says less than the delta chip beside it |
| Recent Activity feed | **Not wanted.** The audit log answers the same question properly, with filters |

## 4. The filter contract

One schema, every widget. Dribee's reason, which applies here identically: each
endpoint had invented its own date handling, so *two widgets on the same screen
could silently answer for two different periods*.

```
period      today | wtd | mtd | qtd | ytd | last_30d | custom
compare_to  previous_period | previous_year | none
```

Filters live in the URL, so a dashboard can be bookmarked and sent to somebody.

## 5. The rules that keep the figures honest

- **`null` means unknown, never zero.** No previous period means no delta chip,
  not "0%" — "nothing before" is not 0% growth.
- **A failed fetch shows a failure**, never a quiet dash. A dash where a figure
  should be reads as "business is quiet", which is the opposite of "we could not
  load it".
- **Every KPI tile links somewhere.** A tile that cannot be drilled into does
  not belong on a dashboard.
- **`invertDelta`** for the tiles where a rise is bad news — overdue invoices.
  The arrow follows the number; only the colour carries whether that movement
  was wanted.
- **No figure is computed in the frontend** (M10 definition of done).

## 6. Speed

Three layers, all borrowed:

1. **Counts — 60 s cache.** Already built, keyed by the tile set so two admins
   with the same permissions share an answer.
2. **Charts — 15 minute cache**, keyed on `widget + period + compare_to + from +
   to`. Charts are the expensive part: twelve months of grouped rows.
3. **Separate requests for tiles and charts.** The tiles paint while the charts
   are still loading, rather than the whole screen waiting for the slowest query.

## 7. Colour

The palette lives in CSS variables and the theme tokens, never in a component —
which is already this app's rule (`theme/tokens.ts`; a hex code in a page is a
bug). Charts read the variables at render time, so a brand change reaches every
series without touching a chart.

## 8. Not adopted from Dribee

- **Five dashboards behind a registry.** One office, one dashboard.
- **A warehouse filter.** Nothing here plays that role.
- **Snapshot rows in a table.** Dribee persists chart snapshots; at this data
  size an in-process cache is the same answer without a migration.
