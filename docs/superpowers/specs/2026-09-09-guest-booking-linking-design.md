# Guest Event Booking — Email Verification and Member Linking

- **Date:** 2026-09-09
- **Status:** Design approved. Not implemented.
- **Modules touched:** M1 (auth), event registration, billing (read paths only)

## Problem

A guest event booking and a membership registration collect almost the same
company data, and the two never meet.

The guest event form asks for Company Name, Company Email, Company Mobile, GST
Number, Address, Pincode, Country, State and City. That is the membership form's
company block, missing only company type, membership categories, KYC documents
and the fee plan. `GuestRegisterView.tsx` sends the company name into both
`full_name` and `company_name`, so a guest booking is already a **company**
record, not a person.

Three consequences today:

1. **A pending applicant is stranded.** Registration creates a login with no
   password and status `PENDING_APPROVAL`, which cannot sign in. If that
   applicant wants to attend an event while waiting, he must book through the
   public guest form and retype every company field he supplied days earlier. The
   resulting `GuestRegistrant` row has no link to his application.
2. **History is lost at approval.** `listMyBookings` filters on
   `EventRegistration.member_id`. A guest booking has `member_id = NULL`, so once
   the applicant is approved, sets a password and signs in for the first time,
   his earlier booking and its invoice do not appear anywhere in his account.
3. **A guest cannot retrieve their own invoice.** The booking link
   (`/events/booking/<token>`) expires after 30 days, and `GET /invoices/:id/pdf`
   requires a session. A company that attends three events a year holds three
   separate links, all dead by the time their accountant needs the invoices for a
   GST return.

## Decisions taken

Recorded because several of these close off designs that would otherwise look
obvious later.

| # | Decision | Rationale |
|---|---|---|
| D-1 | **No login before admin approval.** The account remains unusable until the approval email issues the set-password link. | Client decision, 2026-09-09. Rules out creating a usable account at registration time. |
| D-2 | **A pending applicant books as an ordinary guest** and retypes his company details. | Client decision, 2026-09-09. A "book from your application track link" option was offered and declined. |
| D-3 | **Build a `/my-bookings` lookup page** — email plus OTP, no account. | Client decision, 2026-09-09. |
| D-4 | **No GSTIN matching.** | Fuzzy matching on a typed tax number merges distinct companies, and unmerging is expensive. Verified email is the only match key. |
| D-5 | **Auto-attach a booking whose verified email matches an active account**, without changing the price and without telling the booker. | An OTP-verified email is the same proof standard as a login. Not attaching leaves orphan rows. Telling the booker would reveal which emails have accounts. |
| D-6 | **Lookup session lasts 30 minutes.** | Long enough to download invoices, short enough to matter on a shared machine. |
| D-7 | **Prices are never adjusted and issued invoices are never rewritten.** | The booking summary already promises "Booking locks your price". An invoice raised to a non-member carries that party's name, address and GST position; re-addressing it after issue breaks reconciliation. Also, no partial-refund or credit-note mechanism exists — `refund.service.ts` only handles full refunds raised by cancelling a whole event. |
| D-8 | **Every behaviour change sits behind a `SystemSettings` flag, default OFF.** | The same mechanism `directory.enabled` and `billing.charge_application_fee` already use. With the flags off the deployed system behaves exactly as it does today, and a problem is undone from the admin Settings screen in one click rather than by a redeploy. |
| D-9 | **Linking runs after the set-password transaction, best-effort.** | A failed link is recoverable by re-running the backfill. A member who cannot set a password is locked out of his own account. `activation.service.ts` already makes this call for document copying: the membership must be atomic, the copy must not be able to break it. |

## Out of scope

- Any change to the login gate, the approval workflow, or the set-password flow
  beyond the single linking step described below.
- Member pricing for pending applicants. A guest booking is charged the
  non-member rate, locked at booking.
- Any admin screen. Nothing in the admin app changes.
- Accounting integration (parked project-wide).

## Design

### Principle

**Ownership is never rewritten; visibility is added.**

`EventRegistration` and `Invoice` each carry a CHECK constraint requiring exactly
one of `member_id` / `guest_registrant_id`. A guest booking's rows stay
guest-owned for their whole life. Linking adds a pointer on the
`GuestRegistrant` row, and member-facing read paths follow that pointer. This
keeps the CHECK constraints intact and keeps every issued invoice exactly as it
was issued.

### Feature flags

Two new keys in `SETTING_KEYS`, read with `getBooleanSetting(key, false)`:

| Key | Default | Off means |
|---|---|---|
| `events.guest_booking_otp` | `false` | The guest booking form and `registerAsGuest` behave exactly as they do today. No code is requested, none is required, `email_verified_at` is never written. |
| `events.booking_lookup_enabled` | `false` | `/my-bookings` and both lookup endpoints answer 404. |

Deployment order is therefore safe in any sequence: backend first, frontend
first, or together. With both flags off, no request takes a different path than
it does today.

**Linking carries no flag of its own.** It acts only on rows with a non-NULL
`email_verified_at`, and those rows exist only if `events.guest_booking_otp` has
been on. With the flag off it matches nothing. It is inert by construction rather
than by a switch, which is one fewer thing to get wrong.

### Schema

One new migration. No applied migration is modified.

```
enum OtpPurpose {
  SIGNUP_VERIFY
  PASSWORD_RESET
  LOGIN_2FA
  GUEST_BOOKING_VERIFY   -- new: proves the email at booking time
  BOOKING_LOOKUP         -- new: proves the email at lookup time
}

model GuestRegistrant {
  ...
  email_verified_at  DateTime?  -- NULL for every pre-existing row
  linked_member_id   BigInt?    -- FK Members.id, ON DELETE SET NULL, indexed
}
```

Two OTP purposes rather than one, following the rule the existing enum already
states: the purpose is part of the lookup key, so a code issued for one action
cannot be replayed against another.

`GuestRegistrant.email` is already indexed, so the match lookup needs no new
index on that column.

### Backend

**Guest booking verification**

- `POST /events/booking/request-otp` — body `{ email }`. Issues a
  `GUEST_BOOKING_VERIFY` code. Mounted behind the existing `rateLimiters.otp`
  (3 per 15 minutes per identifier). Always answers success; it reveals nothing,
  because it says only that a code was sent to an address the caller typed.
- `registerAsGuestSchema` gains an **optional** `otp_code`. Optional in the
  schema, not required — a required field would reject every booking from a
  frontend that has not shipped yet. The service demands it only when
  `events.guest_booking_otp` is on, and rejects the booking with a clear message
  if it is missing.
- `registerAsGuest` verifies and consumes the code **inside the booking
  transaction**, before seats are taken, and stamps `email_verified_at`. A
  booking and its email proof commit together or neither does. This mirrors
  `verifyOtp` in `auth.service.ts`, including its attempt-count and expiry
  handling.
- On success, if an `ACTIVE` `User` exists with that email and owns a `Member`,
  set `linked_member_id` immediately (D-5). Price is unaffected.

**Linking at first sign-in**

`setInitialPassword` (`auth.service.ts`) keeps its existing transaction exactly
as it is. Linking runs **after** that transaction commits, best-effort (D-9):

- resolve the `Member` where `primary_user_id = user.id`;
- update every `GuestRegistrant` where
  `email = user.email AND email_verified_at IS NOT NULL AND linked_member_id IS NULL`,
  setting `linked_member_id`;
- write an audit row naming how many rows were attached;
- on failure, log and return normally. **The password set must never be undone by
  a linking failure** — the member would be locked out of the account he was just
  given, to save him from missing a row on a list. `activation.service.ts` makes
  the identical trade for document copying.

A `scripts/` backfill re-runs the same match for any member whose linking failed
or who was approved before this shipped. Because the update is
`linked_member_id IS NULL`-guarded, running it repeatedly is safe.

Only verified rows are attached. Pre-existing guest rows have
`email_verified_at = NULL` and are therefore never auto-attached — see
*Existing data* below.

**Member read paths**

`listMyBookings(memberId)` and `listOwnInvoices(memberId)` also return rows
reached through `GuestRegistrant.linked_member_id`, flagged so the UI can label
them *"booked before membership"*. The rows themselves remain guest-owned.

**Guest lookup**

- `POST /events/bookings/lookup/request-otp` — body `{ email }`. Issues a
  `BOOKING_LOOKUP` code. Same `rateLimiters.otp` throttle.
- `POST /events/bookings/lookup` — body `{ email, otp_code }`. Consumes the code
  and returns every booking made with that email, with its invoice summary, plus
  a lookup token valid 30 minutes (D-6).

  The token is a **signed JWT** carrying only `{ scope: 'booking_lookup', email }`,
  not a stored opaque token. Thirty minutes is short enough that revocation is not
  needed, and this avoids a table and a migration for a credential that expires
  before anyone could act on a revocation. It is signed with the same secret and
  helper shape as `utils/jwt.ts`, but kept in its own module because it is not an
  audience token and must never satisfy `authenticate`.
- `GET /events/bookings/lookup/invoice/:invoiceId/pdf` — guarded by that lookup
  token, and serves the PDF only when the invoice's `guest_registrant.email`
  matches the token's verified email.

A separate endpoint rather than relaxing the authenticated `/invoices/:id/pdf`
route: that route currently demands a session for both audiences, and widening it
would put a token-based bypass on a path that also serves member and admin
downloads.

The *authorisation rule* is nonetheless not duplicated. `member.service.ts`'s
`getInvoicePdf` already owns "may this caller see this invoice", so it gains an
optional `guestEmail` on its viewer argument and matches it against the invoice's
own `guest_registrant.email`. Checking ownership outside that function would leave
two rules that must agree forever, and passing `isAdmin: true` to get past the
existing member check would hand the caller every invoice in the system.

**Lookup returns unverified rows on purpose.** The OTP at lookup time is itself
the proof of inbox ownership, and it is proof taken *now*. Verification at
booking time is a stricter requirement because auto-attaching to a member account
is a durable, unattended write.

### Frontend (customer)

- **Guest event form** — a Verify button beside Company Email, a code field, and
  submit disabled until a code is entered. The existing copy block explaining
  that Company email is where the invoice and booking link go should be extended
  to say why the code is needed.
- **`/my-bookings`** — email field, OTP step, then a list of bookings with status,
  amount, and an invoice download per row. Public route, no guard.
- **My Events / My Invoices** — render the "booked before membership" label on
  linked rows.

No admin changes.

## Data flows

**A — Pending applicant books an event**

1. 1 Sept: registers. `User` created `PENDING_APPROVAL`, no password. Cannot sign in (D-1).
2. 5 Sept: books an event through the public guest form, retyping his company
   details (D-2). Verifies the company email by OTP. `GuestRegistrant` written
   with `email_verified_at` set. His `User` row exists but is
   `PENDING_APPROVAL`, not `ACTIVE`, so the D-5 attach does not fire and
   `linked_member_id` stays NULL. Charged the non-member rate, locked (D-7).
3. 20 Sept: admin approves. Set-password email arrives.
4. He sets his password. In that same transaction the 5 Sept booking is attached
   to his member record. He signs in and sees the booking and its invoice, labelled
   as booked before membership. The invoice PDF is unchanged from the day it was issued.

**B — Company that never applies**

Books three events across a year, each verified by OTP. Each booking still emails
its own 30-day link. In December the accountant opens `/my-bookings`, enters the
company email, receives a code, and downloads all three invoices. Nothing is
created; nothing expires.

**C — Existing member books without signing in**

Verified email matches an `ACTIVE` account, so `linked_member_id` is set at
booking (D-5). The booking appears in their account. They paid the guest rate,
because they chose not to sign in, and that is not adjusted (D-7). The form does
not tell them their email is known.

## Security

- **Enumeration.** Both `request-otp` endpoints answer identically for every
  address. `/my-bookings` returns an empty list rather than "no such email", so
  the page cannot be used to test whether an address has ever booked.
- **Brute force.** Both new purposes reuse the existing OTP constants — 6 digits,
  10-minute expiry, 5 attempts then retirement — and both endpoints sit behind
  `rateLimiters.otp`.
- **Token handling.** The lookup token is random, stored only as a hash, and
  scoped to one email. It grants read access to bookings and invoice PDFs for
  that email and nothing else.
- **The reason verification is mandatory.** Without it, a stranger could book
  under a real company's email, leave the invoice unpaid, and have that debt
  attach to the company's account at approval.

## Existing data

Guest rows created before this change have `email_verified_at = NULL`, so they are
**never auto-attached** to a member account. This is deliberate: those emails were
never proven, and back-filling them would import exactly the risk the OTP exists
to remove.

They remain fully reachable through `/my-bookings`, where the OTP proves
ownership at the moment of reading.

**Open question for the client:** whether an admin should be able to attach a
pre-existing guest booking to a member manually after checking it. Not designed
here, and not required for this work.

## Testing

Unit tests:

- a booking is refused with a missing, wrong, expired or already-consumed code;
- the code is consumed in the same transaction as the booking — a booking that
  rolls back leaves the code live;
- seats are not taken when verification fails;
- linking at set-password attaches only rows with a matching email **and** a
  non-NULL `email_verified_at`, and never re-attaches an already-linked row;
- linking is idempotent if set-password is somehow replayed;
- lookup returns only bookings for the OTP'd email, and an unknown email returns
  an empty list, not an error;
- the lookup token cannot fetch an invoice belonging to another email;
- an invoice's `member_id` / `guest_registrant_id` are unchanged by linking;
- **with `events.guest_booking_otp` off, a booking with no `otp_code` succeeds
  and writes no `email_verified_at`** — that is the "nothing changed" test and
  the most important one here;
- with `events.booking_lookup_enabled` off, both lookup endpoints 404;
- a linking failure leaves the password set intact and the member able to sign in;
- the backfill is idempotent — a second run attaches nothing further.

Then the existing Self-Test Agent. No new testing agent.

## Ambiguities to confirm before coding

1. **Label wording** for linked rows — "Booked before membership" is a
   placeholder, not client-approved copy.
2. **Attendee emails.** Linking matches on the *company* email only. A booking
   whose attendees are the member's staff is not matched by attendee address, and
   is not intended to be.
3. **Manual admin attach** for pre-existing unverified rows — see *Existing data*.
