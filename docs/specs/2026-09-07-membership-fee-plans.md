# Membership Fee Plans — design spec

**Date:** 2026-09-07 · **Module:** M2 (masters) · **Status:** draft, awaiting approval
**Supersedes:** the fee-structure screen shipped 2026-08-13 (A-11).
**Blocked by:** nothing. **Blocks:** M6 renewal.
**Partly superseded by:** `2026-09-07-membership-purchase-flow.md` — the plans, pricing and
versioning below all stand, but the plan is chosen in the member portal after approval rather than
on the signup form, so §6.5's `?feePlan=` wiring and `MembershipApplications.fee_plan_id` fall
away. `MembershipTerms.fee_plan_id` remains the record of a member's plan.

---

## 1. The change in one sentence

A fee stops being *one loose price row* and becomes *a named plan that carries
both its joining price and its renewal price*, versioned over time.

## 2. Why

Today a price is `(category, tier, fee_type, amount, duration, dates)`. Three
things the association actually needs, it cannot do:

1. **Name a plan.** The public page derives a label from the month count —
   `12 → "1 year"`, `30 → "30 months"`. Nobody can publish "Best Value".
2. **Guarantee a renewal price exists.** Joining and renewal are two unrelated
   rows joined by nothing. As of today the database holds **one** renewal row
   and it is switched off — so every member approved now would reach renewal
   with no price to charge.
3. **Change a price safely.** There is no record of whether a price rise was
   meant to apply to existing members or only to new ones.

Modelled on the Cursor pricing page (`cursor.com/pricing`, studied 2026-09-07):
one plan, several billing cycles, one price per cycle. What is adopted and what
is deliberately not is recorded in §9.

## 3. What is being removed

| Removed | Reason |
|---|---|
| `MembershipCategory` / `MembershipTier` from pricing | Already dead — `Fees.tsx:604` comments both fields out of the drawer. The columns still hold values from old rows, which is why the current table shows apparent duplicates. |
| `FeeType.EVENT_DEFAULT` | Not a membership price. Belongs with events, not the plan list. |
| The `Charged for` dropdown | Joining and renewal become two columns on one row, not two rows. |
| Free-form `duration_months` | Replaced by four fixed cycles. |

## 4. The shape

One **fee structure** is a named container. Inside it, up to four **plans**, one
per billing cycle. Each plan carries both prices.

```
FEE STRUCTURE  "Membership 2026"                              Live
├─ Monthly     "Starter"      join  ₹3,000   renewal  ₹2,500
├─ Quarterly   "Standard"     join  ₹8,000   renewal  ₹7,000
├─ 6 Months    — not published —
└─ Yearly      "Best Value"   join ₹25,000   renewal ₹20,000
```

Dates, tax and scope live on the **plan**, not the structure, because a price
change touches one cycle at a time. The structure carries only a name and a
status; it exists so the list shows one row per price list rather than four.

## 5. Rules the system enforces

| # | Rule | Enforced by |
|---|---|---|
| R-1 | A cycle appears at most once per structure | `UNIQUE (structure_id, billing_cycle)` |
| R-2 | One live plan per cycle per date range | `btree_gist` exclusion, moved from `FeeStructures` to `FeePlans` |
| R-2b | Publishing is **refused** while a live structure already covers one of the ticked cycles. The old list is never closed automatically | service validation + the create drawer's own guard |
| R-3 | A published plan must have a name, a join price and a renewal price | NOT NULL + service validation |
| R-4 | A structure must publish at least one plan | service validation |
| R-5 | A price with an invoice against it can never be edited in place | service validation, see §7 |
| R-6 | A plan is retired, never deleted, once anything references it | soft delete + FK RESTRICT |
| R-7 | Amounts ≥ 0, tax 0–100 | CHECK constraints, unchanged |

## 6. Screens

### 6.1 List — `/masters/fees`

One row per structure. Components: `PageHeader` · `SearchInput` ·
`FilterDropdown` · `Button variant="primary"` · `Card flush` · `DataTable` ·
`StatusChip` · `Badge` · `RowActions`.

```
Fee Structures                    [Search] [Filters] [+ New structure]
Sr. | Structure        | Plans    | Applies to       | Status
  1 | Membership 2026  | 3 of 4 ! | All members      | Live
  2 | Membership 2025  | 4 of 4   | New members only | Retired
```

`3 of 4` is a `Badge`; the warning variant fires when a cycle is unpublished.
Filters: Status only. `unit="structures"`.

### 6.2 Create drawer

`FormDrawer`. One save publishes every ticked cycle.

```
Name  [ Membership 2026 ]     Copy from  [ Membership 2025 v ]

Cycle     | Plan name    | Join Rs | Renewal Rs | Tax % | Live
Monthly   | Starter      |   3,000 |      2,500 |    18 |  [x]
Quarterly | Standard     |   8,000 |      7,000 |    18 |  [x]
6 Months  |              |         |            |    18 |  [ ]
Yearly    | Best Value   |  25,000 |     20,000 |    18 |  [x]

Effective from [ 01 Apr 2026 ]
```

`Copy from` prefills every cell from an existing structure. Without it an admin
retypes twelve values a year.

### 6.3 Detail drawer, with inline edit

Cycles are rows; the one being edited **expands in place**. No second drawer.

```
> Monthly    Starter      Rs 3,000   Rs 2,500   Live   Edit
> Quarterly  Standard     Rs 8,000   Rs 7,000   Live   Edit
v Yearly     Best Value   Rs 25,000  Rs 20,000  Live   Edit
  +--------------------------------------------------------+
  | Name          [ Best Value ]                           |
  | Join fee      Rs 25,000  ->  [ 28,000 ]                |
  | Renewal fee   Rs 20,000  ->  [ 22,000 ]                |
  | Tax %         [ 18 ]      Applies from [ 01 Apr 2027 ] |
  |                                                        |
  | i 12 members have paid Rs 25,000. Their invoices       |
  |   will not change.                                     |
  |                                                        |
  | [Cancel]  [New members only]  [Apply to everyone]      |
  +--------------------------------------------------------+

! 6 Months is not published        [ + Add plan v ]
```

`+ Add plan` lists **only** cycles absent from this structure. When all four
exist the control is not rendered, so R-1 cannot be violated from the UI.

After saving, the old price collapses into a history list under its cycle:

```
v Yearly   Best Value   Rs 28,000  Rs 22,000   Live   Edit
   from 01 Apr 2027 - applies to all members
   Price history
     Rs 25,000 / Rs 20,000   01 Apr 2026 - 31 Mar 2027
     Retired - 12 members paid this
```

### 6.4 Public — `/membership`

One card per live plan of the live structure. Tax-inclusive figure leads,
because that is the number the invoice carries. Renewal price shown in small
type so a member is never surprised a year later. Existing empty state
("Plans are being finalised") is retained for the no-live-plan case.

### 6.5 Touched, not rebuilt

| Screen | Change |
|---|---|
| `/signup?plan=` | reads a plan id instead of a fee id; server revalidation unchanged |
| `/applications/:id` | approval panel gains the chosen plan, its term and its renewal price |
| `/members/:id` | profile gains plan name, cycle, and next renewal amount |

## 7. Editing and versioning

The admin sees an edit form. The database keeps every price that was ever
charged. The service decides which of the two happens:

```
Did the join or renewal AMOUNT change?
├─ NO  -> update the row in place. One [Save] button.
└─ YES -> does any InvoiceLine reference this plan?
          ├─ NO  -> update the row in place. One [Save] button.
          └─ YES -> show both scope buttons. On save:
                    1. set old plan effective_to = new effective_from - 1 day
                    2. set old plan is_active = false
                    3. insert a new plan row with the new prices,
                       effective_from as entered, price_scope from the button
```

A name-only or tax-only edit never versions. Amounts do.

**`price_scope` affects the renewal price only.** A joining price change reaches
new applicants either way — existing members do not pay a joining fee again.

| Button | Existing members renew at | New applicants pay |
|---|---|---|
| `Apply to everyone` *(default)* | the new price | the new price |
| `New members only` | their own plan's old price | the new price |

**Retired does not mean inactive for billing.** A retired plan is hidden from
the website and rejected for new applications, but it still prices the renewals
of members sitting on it under `NEW_MEMBERS_ONLY`. It can never be reactivated —
its dates would collide with the live row under R-2 — and never deleted under
R-6.

## 8. Data model

### New: `FeeStructures` (the existing table, repurposed)

| Column | Type | Note |
|---|---|---|
| `name` | varchar(120) | "Membership 2026" |
| `is_active` | boolean | Live / Retired |

Its pricing columns move to `FeePlans`.

### New: `FeePlans`

| Column | Type | Note |
|---|---|---|
| `structure_id` | bigint FK | RESTRICT |
| `billing_cycle` | enum | `MONTHLY` `QUARTERLY` `HALF_YEARLY` `YEARLY` |
| `name` | varchar(120) | "Best Value" |
| `amount` | decimal(14,2) | joining price, pre-tax |
| `renewal_amount` | decimal(14,2) | renewal price, pre-tax |
| `tax_rate` | decimal(5,2) | |
| `currency` | char(3) | INR, per A-3 |
| `effective_from` / `effective_to` | date | `effective_to` NULL = open |
| `price_scope` | enum | `ALL_MEMBERS` (default) / `NEW_MEMBERS_ONLY` |
| `is_active` | boolean | |

`duration_months` is derived from `billing_cycle` (1 / 3 / 6 / 12) and is not
stored twice.

### Foreign keys to repoint

| Column | From | To |
|---|---|---|
| `MembershipApplications.fee_structure_id` | `FeeStructures` | `FeePlans`, renamed `fee_plan_id` |
| `InvoiceLines.fee_structure_id` | `FeeStructures` | `FeePlans`, renamed `fee_plan_id` |

### New column, and the reason it cannot wait

`MembershipTerms.fee_plan_id` — nullable FK, `ON DELETE RESTRICT`.

Nothing reads it until M6. It is written anyway, at approval, because a term
created before this column exists carries no record of which plan was bought.
Every such member becomes unpriceable when the renewal engine is built, and has
to be reconciled by hand. One column now, or a data-repair job later.

`price_scope` is written for the same reason: the intent behind a price change
is only knowable at the moment it is made.

### Data cleanup, required before the migration

From the live database, 2026-09-07:

```
id  fee_type        amount     term  effective_from  active  category
 3  NEW_MEMBERSHIP  20000.00   30    2026-08-24      t       (none)
 4  NEW_MEMBERSHIP  25000.00   12    2026-04-01      t       5
 8  NEW_MEMBERSHIP  25000.00   12    2026-04-01      t       7
17  NEW_MEMBERSHIP  25000.00   12    2026-09-02      t       (none)
```

- Rows 4 and 8 are only distinguishable by a category that is being removed.
  Once flattened they violate R-2. One must be retired.
- Row 3 is a 30-month term, which is not one of the four cycles. Retire it.
- Row 2 is the only `RENEWAL` row and is inactive; it has no counterpart to
  migrate into.

Each surviving row becomes one `FeePlans` row under a generated structure named
`Membership (migrated 2026)`, with `renewal_amount` seeded equal to `amount` and
flagged for an admin to correct. Migrating a guessed renewal price silently is
the one thing this must not do.

## 9. Adopted from Cursor, and not

### Adopted
- One plan, several billing cycles, one price per cycle.
- The plan's identity (name) is stable across cycles; only the price moves.
- Cycle is a first-class choice made before applying, carried into signup.

### Deliberately not adopted
- **The Monthly/Yearly toggle.** Cursor has four products to switch between. With
  one membership a toggle leaves a single card on an empty page, so the four
  cycles are shown as four cards instead.
- **Feature bullets per plan.** Out of scope by decision, 2026-09-07.
- **Sub-tiers (Pro / Pro+ / Ultra).** That is `MembershipTier`, which is being
  removed. Adding tiers later means more structure rows, not a rebuild.

## 10. Out of scope — M6

Stored now, read later. This build must not implement:

- renewal invoice generation
- the `price_scope` resolution at renewal time
- the price-drift report and its bulk "move to current price" action
- the lapsed-member rule (OQ-6)

## 11. Sequencing

Design is signed off before backend work starts.

| # | Phase | Deliverable |
|---|---|---|
| 1 | **Design** | Admin list, create drawer, detail drawer with inline edit and history, public cards. Approved before anything else. |
| 2 | Migration | `FeePlans`, FK repoint, `MembershipTerms.fee_plan_id`, data cleanup |
| 3 | Backend | structure + plan CRUD, publish validation, the versioning rule in §7 |
| 4 | Admin | the approved screens |
| 5 | Customer | `/membership` cards, `?plan=` signup, approval and member panels |
| 6 | Self-test | existing `masters` suite extended |

## 12. Open ambiguities

| # | Question | Blocks |
|---|---|---|
| OQ-6 | A member who lapses and returns — joining price or renewal price? | M6 only. Not this build. **Proposed answer below, awaiting the association's sign-off.** |

### OQ-6 — proposed answer (not yet a decision)

The mechanism already exists. `membership.grace_days` is a live setting, currently **30**, and
today it decides only one thing: how long after expiry a member still gets member pricing on
events (`settings.ts`, used in three places in the event module).

The proposal is to widen what that one number means, rather than introduce a second grace period:

```
expired ≤ membership.grace_days   ->  RENEWAL price   (they were late, not gone)
expired >  membership.grace_days  ->  JOINING price   (they are re-verified, which is what it pays for)
```

Reasoning: the joining fee is not really a price, it is payment for work — document
verification, GST checks, KYC. Someone two months late has documents that are still valid and
there is nothing to re-verify; charging them to join again charges for work nobody did. Someone
gone three years is genuinely being re-onboarded.

Two riders:

- **The member code is always kept**, whichever price applies. It identifies the company, not the
  term; reissuing it would orphan their invoices and their directory history. "New membership"
  here means a new joining fee and re-verification, never a new company record.
- **30 is probably too short for this second job.** It was chosen against an event discount, not
  against a five-figure joining fee, and an invoice can sit unpaid across a festival period. 60
  or 90 would be more defensible — but the number is the association's to set, which is why this
  stays a proposal.

Nothing needs building for this: M6 reads the setting when it exists.
*Design questions A and B were answered 2026-09-07 and are recorded in §13.*

## 13. Decisions taken

| # | Date | Decision |
|---|---|---|
| D-1 | 2026-09-07 | The four cycle labels are **fixed system values** — Monthly, Quarterly, 6 Months, Yearly. An admin names the *plan*, never the cycle. |
| D-2 | 2026-09-07 | `Copy from` is **hidden on the first structure**, when nothing exists to copy, and appears from the second onward. |
| D-3 | 2026-09-07 | A live structure **blocks** a new one covering the same cycle. Publishing does **not** auto-close the current list — the admin closes or retires it first, deliberately. Closing a price list ends what can be sold, and that decision should be visible and attributable, not a side effect of another action. The clash is per **cycle**, so a new structure publishing only a cycle nobody else holds is allowed. |
| D-4 | 2026-09-07 | The detail drawer is **read-only**, with a single **Edit** in its footer. Per-row edit and "add plan" controls are removed: this is the surface someone opens to answer what membership costs, and controls that change prices do not belong beside a question still being asked. |
| D-5 | 2026-09-07 | **Create and edit are one form** — the same four-row grid. Publishing an unpublished cycle is switching its row on, which removes the separate "add plan" flow entirely. |
| D-6 | 2026-09-07 | A structure is **saved whole**, in one request and one transaction, not plan by plan. Four separate PATCHes let a closed tab leave a price list half-changed, and a half-changed price list is the one state nothing downstream can price against. |
| D-7 | 2026-09-07 | The **scope question is asked on create as well as edit**, whenever the new structure covers a cycle that members are still sitting on. Under D-3 a price change is normally made by retiring the old list and publishing a new one, and that path recorded no intent at all — leaving those members priced by a rule nobody chose. |
| D-8 | 2026-09-07 | Confirming a scope shows a **per-cycle breakdown and an annualised rupee total**. Cycles are not comparable un-annualised: ₹300 more per month and ₹300 more per year are different decisions, and a total that added them would say nothing. The dialog also states plainly that nobody is charged today and nobody is back-charged. |
