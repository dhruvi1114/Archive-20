# M5 — Payments, Receipts, Refunds, Reconciliation & Dunning

**Status:** PENDING · **Migration owner:** Agent B · **Blocking OQ:** OQ-4 (gateway provider) — **non-blocking for coding**, the Manual/Mock providers ship the full flow (ADR-008) · **Depends on:** M4 (invoices exist)

## Goal
Money moves correctly, idempotently and auditably. A member pays and becomes active; Accounts records offline payments, refunds and reconciles — with no accounting integration (FR-16 PARKED).

## Agent B — payment core + admin
- Migration: `Payments`, `PaymentWebhookEvents`, `Receipts`, `Refunds` + unique/idempotency indexes. All commented.
- `modules/payment`: `PaymentProvider` registry, `ManualProvider` + `MockProvider`, initiate, verify, webhook handler built to `payment-webhook-security.md` (raw body from ADR-018, timing-safe HMAC, timestamp window, `(provider, event_id)` uniqueness, amount re-verified against our DB), and the single success transaction from `billing-payment.md` §4 — which also flips the M4 term to ACTIVE and the member to ACTIVE.
- Receipts, refunds (requester ≠ approver), settlement-CSV reconciliation report, stuck-payment sweep, dunning job (OVERDUE marking + reminders at T+1/T+7/T+15 from `SystemSettings`).
- Admin screens A-14…A-19.

## Agent A — member billing
- Invoice list/detail, PDF download, initiate + verify, payment result screen (success / failure / **pending-unknown**), payment history, receipt download.
- Customer screens C-19…C-22.

## Contracts frozen
Payment/refund status machines · `PaymentProvider` interface · webhook contract and idempotency key · receipt numbering · money on the wire as a 2dp string.

## Self-test
`billing` suite + `payment-webhook-security.md` §9 in full: MockProvider success → invoice PAID + receipt + term ACTIVE + member ACTIVE, one transaction · duplicate `event_id` → single effect, both 200 · tampered body → 401 · stale timestamp → 400 · amount mismatch → payment FAILED, invoice untouched, alert · client-verify racing the webhook → exactly one update · payment > balance → 409 · refund > refundable → 409 · same admin requests and approves a refund → 403 · dunning job run twice → one reminder.

## Definition of done
- No float anywhere; totals recomputed server-side.
- Every money mutation is transactional with an audit row.
- Gateway/webhook secrets from env only; never logged, never returned.
- Failure copy never implies a charge that did not happen.

## Approval checklist
Gateway (OQ-4) · GST rate and tax-invoice requirement (OQ-8) · refund policy and its effect on the membership term · who may approve refunds · dunning schedule.
