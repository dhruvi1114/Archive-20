# M7 — Event Management

**Status:** PENDING · **Migration owner:** Agent B · **Blocking OQ:** — · **Depends on:** M5 (paid events need invoicing)

## Goal
Admins run an event end to end; members find it, register, pay if needed, and get in on the day.

## Agent B — backend + admin
- Migration: `Events`, `EventRegistrations`, `EventAttendance` + capacity/duplicate constraints.
- `modules/event` admin half: CRUD, publish (states the audience size before confirming), cancel (blocked while paid registrations exist until a refund decision is made), registration list, capacity enforcement (atomic count inside the registration transaction), check-in, attendee export.
- Admin screens A-21…A-24.

## Agent A — member side
- Public + member event listing and detail, register (free → CONFIRMED; paid → PENDING_PAYMENT + invoice → M5 payment flow), cancel registration, my registrations.
- Customer screens C-04 (public), C-24, C-25.

## Contracts frozen
Event/registration status machines · capacity + waitlist rule · registration code format · public vs member-only visibility flag · attendee export columns.

## Self-test
`event` suite: publish makes the event visible publicly and to members; registering twice → 409; registering past the deadline → 422 with the date; capacity boundary — N concurrent registrations on a 1-seat event yield exactly one CONFIRMED; paid registration stays PENDING_PAYMENT until the invoice is PAID, then flips to CONFIRMED; check-in twice → 409; cancel a published event with paid registrations → 409 until handled.

## Definition of done
- Capacity is enforced in SQL inside the transaction, never by a read-then-write race.
- Paid registration and its invoice are created atomically.
- Attendee export matches the on-screen filter.

## Approval checklist
Waitlist in scope or not · cancellation/refund policy for events · whether non-members may register.
