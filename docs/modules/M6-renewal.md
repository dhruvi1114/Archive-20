# M6 — Membership Renewal

**Status:** PENDING · **Migration owner:** Agent B · **Blocking OQ:** OQ-6 (reminder schedule, grace period, expiry behaviour, auto vs manual) · **Depends on:** M4 (terms + invoices exist), M5 (payment flow)

## Goal
Nobody lapses by accident. Terms, reminders and grace behaviour are explicit and visible on both sides.

## Agent B — backend + admin
- Migration: `RenewalReminders` (+ any `MembershipTerms` columns renewal needs; the table itself is created in M4). All commented.
- `modules/renewal`: eligibility, renewal term creation (starts at current expiry — no lost days), renewal invoice via the M5 fee resolution, grace handling, expiry sweep job, reminder scheduling job (one row per `(term, reminder_code)` — DB-enforced no duplicates).
- Admin screens A-20: due/grace/expired buckets, bulk invoice generation, reminder send, extend grace with reason.

## Agent A — member side
- `/membership/me/term`, `/membership/me/renew`, term history.
- Customer screens C-18, C-23 + dashboard banner states: active · expiring soon · in grace · expired (each with the exact consequence spelled out).

## Contracts frozen
Term status machine · reminder codes · grace rules · what expiry actually blocks (directory listing, event registration, portal read-only?).

## Self-test
`renewal` suite: term expiring within window appears in the correct bucket; renewal creates a contiguous term (no gap/overlap — DB unique on active term holds); duplicate reminder insert → constraint blocks; expiry sweep flips status and emits one notification; renewing inside grace restores ACTIVE without a coverage gap.

## Definition of done
- Jobs are idempotent and re-runnable (proved by running the sweep twice — no duplicate invoices or notifications).
- Every bucket count on the admin screen matches a single SQL query, not a client-side filter.
- Member banners state the consequence, not just the status.

## Approval checklist
Reminder schedule · grace length · post-grace behaviour (expire vs suspend) · auto-renew or manual (OQ-6).
