# M8 — Communication & Notifications

**Status:** PENDING · **Migration owner:** Agent B · **Blocking OQ:** OQ-5 (WhatsApp provider, templates, opt-in) · **Depends on:** M3 (recipients), M0 (outbox core — ADR-015)

## Goal
Every transactional message from earlier modules actually gets delivered, observably; and staff can broadcast notices/circulars to a precisely targeted audience.

## Agent B — backend + admin
- Migration: `Notices`, `NoticeAudienceRules`, `NoticeRecipients`. (`NotificationTemplates` and `Notifications` were created in M0 — ADR-015.) All commented.
- `modules/notification` extensions: `WhatsAppChannel` (interface impl throwing `NOT_CONFIGURED` until OQ-5), template CRUD, admin outbox view + retry. The writer, drain job, `EmailChannel` and `InAppChannel` already exist from M0.
- `modules/communication`: notice CRUD, audience resolution + recipient count preview, publish fan-out (batched `INSERT … SELECT` in a transaction), delivery + read report.
- Seed the remaining templates and verify every earlier module's queued triggers render correctly (they have been sending since M0 via `EmailChannel`).
- Admin screens A-25…A-28.

## Agent A — member side
- Notices list/detail + read tracking, notification bell feed, mark read / read-all, unread badge.
- Customer screens C-26, C-27.

## Contracts frozen
Template code list (`notification-architecture.md` §4) · placeholder syntax · `Notifications` row shape · audience rule DTO · retry/backoff policy.

## Self-test
`communication` suite: publishing to a category resolves exactly the fixture count and creates that many recipient + notification rows; drain sends and marks SENT; a forced channel failure retries with backoff then FAILED and is retryable from admin; audience = 0 blocks publish; WhatsApp rows stay QUEUED with a visible reason while unconfigured; no OTP/token/KYC content appears in logs.

## Definition of done
- A dead SMTP server cannot roll back or block any business transaction (proved by forcing a send failure during an approval).
- Fan-out to 1000+ recipients is batched, not looped.
- Every template renders with real data in both email and in-app form.

## Approval checklist
WhatsApp provider + approved templates (OQ-5) · sender identity/domain for email · whether members may opt out of non-transactional notices.
