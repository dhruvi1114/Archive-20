# Payment Webhook Security & Idempotency

The webhook endpoint is the only unauthenticated, state-changing, money-moving route in the system. It gets its own rules.

## 1. Endpoint

`POST /api/v1/webhooks/payments/:provider` — no JWT, no payload decryption (ADR-004 bypass list), signature-verified, idempotent, always fast.

## 2. Raw body preservation (must be built in M0, not M5)

Signature verification hashes the **exact bytes** the provider sent. `express.json()` discards them. M0 therefore registers:

```ts
app.use(express.json({
  limit: '1mb',
  verify: (req, _res, buf) => { (req as any).rawBody = buf; },   // Elvee does this; keep it
}));
```

Retrofitting this in M5 means touching `app.ts` after the shared core is frozen. It is cheap now and disruptive later.

## 3. Verification order (fail closed, in this order)

1. `:provider` is a registered provider → else 404.
2. Signature header present → else 401. **Never** process an unsigned webhook.
3. HMAC over `rawBody` with the provider's webhook secret, compared with `crypto.timingSafeEqual` → else 401 + `warn` log with the source IP.
4. Timestamp within a ±5 min tolerance where the provider supplies one → else 400 (replay defence).
5. `PaymentWebhookEvents` insert with unique `(provider, event_id)`:
   - insert succeeded → first delivery, process it.
   - unique violation → duplicate delivery, **return 200 immediately** and do nothing. Providers retry aggressively; a duplicate must be a no-op, not an error.
6. Process inside the success transaction (`billing-payment.md` §4), which itself re-locks the `Payments` row and re-checks status — belt and braces, because the client-side `/payments/:id/verify` call can arrive at the same instant.

## 4. Response contract

Return **200 within a few seconds** for anything successfully recorded, including duplicates and events we do not care about (`event_type` not handled → store, mark processed, 200). Return non-2xx only when we genuinely could not persist the event, so the provider retries. Never return a stack trace or internal detail. Never make the provider wait on PDF generation or email sending — those are queued (`Notifications`) and drained by a job.

## 5. What is trusted from the payload

Only the provider's identifiers and status. **Amount is verified, never accepted:** the handler re-reads `Payments.amount` from our DB and compares it to the provider's amount; a mismatch marks the payment `FAILED` with `failure_reason='amount_mismatch'`, does not touch the invoice, logs at `error` and alerts. Invoice/member linkage always comes from our own `Payments` row, resolved by `provider_order_id`, never from a client-supplied id in the payload.

## 6. Abuse handling

Signature failures are logged at `error` with IP and provider, counted, and alerted above 3/hour (`observability.md` §6). Rate limit the webhook path per IP generously enough for legitimate provider retries (e.g. 100/min) and below anything abusive. Optional IP allowlist if the provider publishes stable ranges — nice to have, never the primary control, because signatures are.

## 7. Reconciliation as the safety net

If a webhook is lost entirely (provider outage, our downtime): a job re-queries `provider.fetchPayment()` for `Payments` stuck in `INITIATED`/`PENDING` older than 15 minutes, and the settlement-CSV reconciliation report (`billing-payment.md` §8) catches the rest. Stored raw payloads in `PaymentWebhookEvents` make manual replay possible without contacting the provider.

## 8. Secrets

Webhook secret in env (`PAYMENT_WEBHOOK_SECRET_<PROVIDER>`), never in the DB, never logged, rotated by re-registering the endpoint. Distinct secrets per environment; a staging webhook must never validate against production's secret.

## 9. Test cases (Sentinel `billing` suite)

Valid signature + new event → processed once · same `event_id` twice → single effect, both 200 · tampered body → 401 · missing signature → 401 · stale timestamp → 400 · amount mismatch → payment FAILED, invoice untouched, alert raised · unknown `event_type` → stored + 200 · client `verify` and webhook racing → exactly one invoice update · unknown provider → 404.

## 10. MVP position

Until OQ-4 names a gateway, `MockProvider` implements this exact contract (HMAC over raw body, event id, timestamp) so the handler, the tests and the failure paths are real from M5. Swapping in the real provider is one adapter file plus the secret — **not** a redesign of this endpoint.
