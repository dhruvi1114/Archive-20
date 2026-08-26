# Billing & Payment

## 1. Money rules

- Every monetary column `Decimal(14,2)`; every calculation server-side in Prisma `Decimal`. No floats, no client-supplied totals.
- Currency `INR` only (A-3). Column exists so multi-currency is a data change later.
- Rounding: half-up to 2 decimals at line level, then summed. Tax computed per line, not on the total.

## 2. Fee resolution

At invoice time the service resolves the effective `FeeStructures` row:

```sql
WHERE category_id = $c
  AND (tier_id = $t OR tier_id IS NULL)
  AND fee_type   = $type
  AND is_active
  AND effective_from <= CURRENT_DATE
  AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)
ORDER BY tier_id NULLS LAST, effective_from DESC
LIMIT 1
```
Tier-specific beats category-wide; newest effective row wins. No match → `409 CONFLICT` with an i18n message telling the admin to configure a fee (never a silent ₹0 invoice).

## 3. Invoice lifecycle

```
DRAFT ──issue──▶ ISSUED ──partial payment──▶ PARTIALLY_PAID ──full payment──▶ PAID (terminal)
  │                 │                             │
  │                 └──due_date passed (job)──▶ OVERDUE ──payment──▶ PAID
  └──cancel──▶ CANCELLED (terminal)        ISSUED|OVERDUE ──cancel──▶ CANCELLED
```
- `PAID` and `CANCELLED` are terminal. A wrong `PAID` invoice is corrected by a refund, never by editing history.
- Only `DRAFT` invoices are editable. `ISSUED`+ are immutable except `status`, `amount_paid`, `balance_due`, `pdf_path`.
- Auto-issued invoices: membership approval (M4), renewal (M6), paid event registration (M7). Admin can also create ad-hoc invoices (`invoice_type = OTHER`).

## 4. Payment flow (online)

```
Member clicks Pay
  → POST /payments/initiate {invoice_id}
      guard: invoice belongs to member, status ISSUED|PARTIALLY_PAID|OVERDUE, balance_due > 0
      Payments row (INITIATED) + provider.createOrder(amount, currency, receipt=payment_number)
      returns provider order payload (no secrets)
  → member completes on the provider
  → TWO independent confirmations, both idempotent:
      (a) POST /payments/:id/verify   — client callback, signature verified server-side
      (b) POST /webhooks/payments/:provider — provider push, signature verified, event stored
  → first one to arrive wins; the second is a no-op (unique provider_payment_id + webhook event id)
```

### Success handler (single transaction)
```
BEGIN
  lock Payments row FOR UPDATE; if already SUCCESS → return (idempotent no-op)
  Payments.status = SUCCESS, provider_payment_id, paid_at
  Invoices.amount_paid += amount; balance_due = total - amount_paid
  Invoices.status = balance_due = 0 ? PAID : PARTIALLY_PAID
  insert Receipts (receipt_number)
  if invoice_type IN (MEMBERSHIP, RENEWAL) and PAID:
       MembershipTerms.status = ACTIVE; Members.status = ACTIVE; Members.current_term_id = term
       insert MemberStatusHistory
  if invoice_type = EVENT and PAID: EventRegistrations.status = CONFIRMED
  insert Notifications (payment received + receipt, membership activated)
  insert AuditLogs
COMMIT
```
Failure → `Payments.status = FAILED` + `failure_reason`; invoice untouched; member may retry (a new `Payments` row, never a mutated one).

## 5. Offline / manual payment (ManualProvider, ADR-008)

`POST /admin/payments/record` (`payment.record`): amount, method (NEFT/CHEQUE/CASH/UPI), reference, paid_at, optional proof upload. Runs the **same** success handler. This is what makes M5 shippable before OQ-4 is answered.

## 6. Provider abstraction

```ts
interface PaymentProvider {
  readonly code: string;
  createOrder(input: {amount: Decimal; currency: string; reference: string; member: MemberRef}): Promise<ProviderOrder>;
  verifyCallbackSignature(raw: string, headers: Record<string,string>): boolean;
  fetchPayment(providerPaymentId: string): Promise<ProviderPayment>;
  refund(input: {providerPaymentId: string; amount: Decimal; reason: string}): Promise<ProviderRefund>;
}
```
Registry keyed by `code`; active provider from `SystemSettings.payment_provider`. Implementations: `ManualProvider` (MVP), `MockProvider` (tests), `<Gateway>Provider` (one file, after OQ-4). Keys live in env, never in DB, never in logs.

## 7. Refunds

`REQUESTED → PROCESSING → COMPLETED | FAILED`, or `REQUESTED → REJECTED`. Rules: refund amount ≤ (payment amount − already refunded); requester ≠ approver (both need `refund.manage`, different admin ids); on `COMPLETED` the payment moves to `REFUNDED`/`PARTIALLY_REFUNDED` and the invoice reopens to `PARTIALLY_PAID`/`ISSUED`. Membership consequences of a refund (suspend the term?) require a decision — flagged as OQ-8b, default MVP behaviour: term untouched, admin decides manually.

## 8. Reconciliation (no accounting integration — FR-16 is PARKED)

`GET /admin/payments/reconciliation` compares, for a date range: platform `Payments` marked SUCCESS vs provider settlement report (CSV upload for MVP). Output: matched, missing-on-platform, missing-at-provider, amount mismatches. This is an internal report only — **nothing is pushed to Tally/Zoho/QuickBooks/Refrens/Vyapar.**

## 9. Documents

Invoice PDF and receipt PDF generated server-side on issue/payment, stored under `backend/src/public/../invoices/` **outside** the static root, served only through authorised endpoints. Regeneration is allowed; the stored number never changes.

## 10. Dunning

Daily job: mark `ISSUED` invoices past `due_date` as `OVERDUE`, queue a reminder notification at T+1, T+7, T+15 (configurable via `SystemSettings`). Overdue membership invoices feed the renewal/suspension rules in M6 (OQ-6).
