# Notification Architecture

## 1. Principle (ADR-010; outbox tables + drain job + EmailChannel are built in M0 per ADR-015)

Business services never call SMTP/WhatsApp inline. They insert `Notifications` rows **inside the same transaction** as the business change. A drain job dispatches them. Consequence: a dead mail server can never roll back an approval, and every message is observable, retryable and auditable.

## 2. Pipeline

```
Service (in txn) ──▶ Notifications (QUEUED, next_attempt_at = now)
                              │
        drain job (every 60s, batch 50, FOR UPDATE SKIP LOCKED)
                              ▼
                      resolve NotificationTemplates (code, channel, locale)
                      render body with payload_json
                              ▼
        ┌───────────────┬───────────────┬───────────────┐
        ▼               ▼               ▼
   EmailChannel    WhatsAppChannel   InAppChannel
   (nodemailer)    (provider API,    (no send; row itself
                    unwired OQ-5)     is the in-app item)
        └───────────────┴───────────────┘
                              ▼
              SENT (sent_at) | FAILED (error, attempt_count++,
              next_attempt_at = now + 2^attempt minutes, max 5 attempts)
```

## 3. Channel interface

```ts
interface NotificationChannel {
  readonly channel: 'EMAIL' | 'WHATSAPP' | 'IN_APP';
  send(msg: RenderedNotification): Promise<{providerMessageId?: string}>;
}
```
`WhatsAppChannel` ships as an interface implementation that throws `NOT_CONFIGURED` until OQ-5 is answered; rows targeting it stay `QUEUED` and are visible in the admin outbox rather than silently lost.

## 4. Templates

`NotificationTemplates(code, channel, locale)`, body with `{{placeholders}}`. Content is authored in i18n-friendly rows, not in code. Seeded set:

| code | Channels | Trigger |
|---|---|---|
| `auth.signup_otp` | EMAIL | signup |
| `auth.password_reset` | EMAIL | forgot password |
| `application.submitted` | EMAIL, IN_APP | member submits |
| `application.stage_approved` | IN_APP | non-final stage approve |
| `application.returned` | EMAIL, IN_APP | return for correction |
| `application.rejected` | EMAIL, IN_APP | reject |
| `application.approved` | EMAIL, IN_APP | final approve |
| `application.pending_review` | IN_APP | to stage approvers |
| `invoice.issued` | EMAIL, IN_APP | invoice issued |
| `invoice.overdue` | EMAIL, IN_APP | dunning job |
| `payment.received` | EMAIL, IN_APP | payment success (receipt attached) |
| `payment.failed` | IN_APP | payment failure |
| `refund.completed` | EMAIL, IN_APP | refund done |
| `membership.activated` | EMAIL, IN_APP | member becomes ACTIVE |
| `membership.renewal_reminder` | EMAIL, IN_APP | T-15/T-7/T-3/T-0 (T-0 = expiry date) |
| `membership.expired` | EMAIL, IN_APP | grace period ends |
| `membership.suspended` | EMAIL, IN_APP | admin suspends |
| `event.registration_confirmed` | EMAIL, IN_APP | registration confirmed |
| `event.reminder` | EMAIL, IN_APP | T-1 day |
| `event.cancelled` | EMAIL, IN_APP | admin cancels |
| `notice.published` | EMAIL, IN_APP | notice/circular publish |
| `profile.change_decided` | IN_APP | change request decided |

M6 reminders are raised by the hourly `membership.renewal` job: a stage missed because the invoice was raised late is skipped, never sent in a burst, and no reminder sends while a payment claim is under verification.

## 5. Broadcast (notices)

Publishing a notice inserts `NoticeRecipients` for the resolved audience and one `Notifications` row per recipient per enabled channel — in a transaction, batched (`INSERT … SELECT`, not a loop). Large audiences are chunked at 1000 rows per statement. The publish endpoint returns the recipient count so the admin sees the expected result before/after.

## 6. In-app notifications

`Notifications` rows with `channel = IN_APP` are the member's bell feed: `GET /notifications/me` (unread first), `read_at` set on open. Badge count is a single indexed count query, cached 30 s client-side.

## 7. Preferences (MVP scope)

No per-member channel preferences in MVP; transactional messages always send. `SystemSettings` holds global on/off switches per channel so an admin can mute WhatsApp/email globally. Per-member opt-out is post-MVP (and legally required before any marketing-style broadcast — flag for the client).

## 8. Failure handling & observability

- Max 5 attempts, exponential backoff, then `FAILED` and visible in `GET /admin/notifications` with the error.
- Admin can retry a failed row (resets `attempt_count`, requeues).
- `JobRuns` records each drain sweep: processed, sent, failed.
- Never log message bodies containing OTPs, tokens or KYC data — log `template_code`, recipient id and status only.
