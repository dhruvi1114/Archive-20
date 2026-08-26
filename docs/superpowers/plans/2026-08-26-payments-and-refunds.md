# Payments, Refunds and Guest-Billable Invoices (Plan 2b)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Finish the money model that M5 left half-built, so event registration has somewhere to record a payment, a refund, and a bill addressed to someone who is not a member.

**Why now:** `database-design.md` §D specifies `Payments`, `Receipts` and `Refunds`. Only `Receipts` was built, and it hangs off the invoice directly. The event module needs all three: registrations are paid offline and verified by staff, a cancelled event refunds everyone, and non-members must be billable. Building events on the current shape would mean migrating live financial data later.

**Spec:** `docs/database-design.md` §D, plus `docs/superpowers/specs/2026-08-26-event-module-schema.md` §4.

**Migration owner:** Agent B.

## Global Constraints

Same as the other M7 plans.

- **Integer enums** (`Int @db.SmallInt` + code map) on **new** tables only. `Invoices` keeps its existing string enums — it is an M4 table with live rows, and converting it would mean rewriting an applied migration.
- **`bigint` keys, no `uuid`.** Human-facing identity is the `payment_number` / `refund_number`, same shape as `invoice_number` and `receipt_number`.
- **FK actions:** `CASCADE` for owned children, `SET NULL` for pointers, `NO ACTION` everywhere else. Financial rows are `NO ACTION` — never cascade-deleted.
- **Migration wrapped in `BEGIN;` … `COMMIT;`.**
- **`COMMENT ON` for every new table and column.**
- **Audit block on every new table**, with the at-most-one-actor `CHECK`.
- **Money** `Decimal(14,2)`, currency `char(3)` default INR.

## Deviation from `database-design.md`, stated deliberately

The spec has `Receipts.payment_id` as the only link, with no `invoice_id`. The built table has `invoice_id` and `member_id` and one live row. This plan **adds** `payment_id` rather than replacing the existing columns: dropping them would break `renderReceiptPdf` and the member receipt screen for no gain. `Receipts` therefore carries both — the payment it acknowledges, and the invoice it closes.

---

### Task 1: `Payments` and `Refunds`

**Files:**
- Create: `backend/prisma/schema/billing.prisma`
- Modify: `backend/prisma/schema/application.prisma` (`Receipt` gains `payment_id`; `Invoice` gains the back-relation)
- Create: migration `m5_add_payments_and_refunds`

**Interfaces:**
- Produces: models `Payment` (`Payments`), `Refund` (`Refunds`); code maps in Task 2.

- [ ] **Step 1: Write the models**

`Payment` per `database-design.md` §D, with these differences, each for a reason:
- `method`, `status` are `Int @db.SmallInt` with code maps (new-table convention), not native enums.
- `member_id` is **nullable**, paired with `guest_registrant_id` in Task 3 — a guest pays too.
- Full audit block.
- `CK amount > 0`, `CK status IN (0..6)`, `CK method IN (0..5)`.
- `provider_order_id` / `provider_payment_id` unique where not null, so a gateway callback cannot be applied twice (R-7).

`Refund` per §D, `payment_id` `NO ACTION`, `CK amount > 0`, status codes 0..4, plus `refund_number varchar(30) U` so a refund is quotable to a member the way an invoice is.

`Receipt` gains `payment_id BigInt?` FK → `Payments`, `NO ACTION`, unique where not null.

- [ ] **Step 2: Generate, wrap, add constraints, comments and the backfill**

The backfill creates one `Payments` row for each existing `Receipts` row (there is exactly one today), method `NEFT`, provider `MANUAL`, status `SUCCESS`, `paid_at` = the receipt's `paid_at`, and points the receipt at it. Without this, a receipt would exist with no payment behind it and the two-way link would be a lie from day one.

- [ ] **Step 3: Apply, verify, prove the guards**

`npx prisma migrate dev` → `migrate status` → `db:check-comments` (new tables must not appear). Then prove by hand that a second payment reusing a `provider_payment_id` is rejected, and that `amount = 0` is rejected.

- [ ] **Step 4: Commit**

---

### Task 2: Recording a payment is what marks an invoice paid

**Files:**
- Create: `backend/src/modules/billing/payment.constants.ts`
- Modify: `backend/src/modules/member/member.service.ts` (`applyInvoicePayment`)
- Test: `backend/src/modules/member/member.paymentRecord.test.ts`

**Interfaces:**
- Produces: `PAYMENT_METHOD`, `PAYMENT_STATUS`, `REFUND_STATUS`; `applyInvoicePayment` keeps its signature and gains a `Payments` write.

- [ ] **Step 1: Write the failing test** — paying an invoice creates exactly one `Payments` row with the invoice total, provider `MANUAL`, status `SUCCESS`, and the receipt points at it. A second payment on an already-PAID invoice still throws before writing anything.

- [ ] **Step 2: Implement inside the existing transaction.** The payment row is created *before* the receipt, and the receipt's `payment_id` is set from it — invoice → payment → receipt, in that order, all or nothing.

- [ ] **Step 3: Full suite, lint, typecheck, commit.**

---

### Task 3: An invoice can be addressed to a guest

**Files:**
- Create: `backend/prisma/schema/event.prisma` (`GuestRegistrants` only — the rest of the event tables come in Plan 2)
- Modify: `backend/prisma/schema/application.prisma` (`Invoice.member_id` → nullable, add `guest_registrant_id`)
- Modify: `backend/prisma/schema/billing.prisma` (`Payment` likewise)
- Create: migration `m7_add_guest_registrants_and_guest_billing`

**Interfaces:**
- Produces: model `GuestRegistrant` (`GuestRegistrants`).

- [ ] **Step 1: `GuestRegistrants`** — name, designation, company, email, phone, GST, PAN, full address, audit block. No `password_hash`, no `Users` row: a guest is a customer of one event, not an account.

- [ ] **Step 2: Make the two financial tables billable either way**

`Invoices` and `Payments` each get `member_id` nullable plus `guest_registrant_id`, and a `CHECK` that **exactly one** is set:

```sql
CHECK (("member_id" IS NOT NULL) <> ("guest_registrant_id" IS NOT NULL))
```

This is the pattern `ApprovalRequests` already uses for its two subject FKs, and `AuthTokens` for its two audiences — so it is the project's established way of saying "one of these two, never both, never neither".

- [ ] **Step 3: Prove nothing existing broke.** Every current invoice has a `member_id`, so the new CHECK must pass on all three live rows before the migration commits. Verify the count of invoices with neither set is zero.

- [ ] **Step 4: Audit every read path that assumes `member_id` is present.**

Run `grep -rn "member_id" src/modules/member/member.service.ts src/helpers/pdf` and confirm each invoice/payment read either scopes by member (fine — guests never hit those endpoints) or handles null. This step is the risk in this plan: making a NOT NULL column nullable is invisible to the type-checker only if Prisma is regenerated, so **run `npm run typecheck` and fix every new null-check error rather than casting it away.**

- [ ] **Step 5: Full suite, lint, typecheck, commit.**

---

## Self-review

**Spec coverage.** `database-design.md` §D `Payments` → Task 1. `Refunds` → Task 1. `Receipts.payment_id` → Task 1 (added, not replacing). Event schema spec §4 `PaymentSubmissions` → **not here**; it belongs with the event registration work in Plan 3, and now has a real `Payments` row to reference on verification.

**Deliberate deviations, both stated above:** integer enums on the new tables while `Invoices` keeps string enums, and `Receipts` keeping `invoice_id` alongside the new `payment_id`.

**Biggest risk:** Task 3 Step 4. Making `Invoice.member_id` nullable changes a type every billing read depends on. The mitigation is that the type-checker surfaces each one, and the instruction is explicit that they be handled rather than cast away.
