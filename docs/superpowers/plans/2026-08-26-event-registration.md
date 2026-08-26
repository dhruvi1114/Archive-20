# Event Registration and Payment Implementation Plan (Plan 3)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A member books seats for named colleagues, or a non-member books for themselves; the seats are held, an invoice is raised, staff verify the offline payment, and unpaid holds release themselves.

**Architecture:** Seats are held by one guarded `UPDATE` inside the registration transaction, never read-then-write. Price is frozen onto each attendee row at registration time, so paying later never changes what is owed. Approval, when the event asks for it, sits *before* the invoice exists — so rejecting costs nothing to reverse.

**Spec:** `docs/superpowers/specs/2026-08-26-event-module-design.md` and `-schema.md`.

**Depends on:** Plan 1 (`MemberUsers` — the attendee picker), Plan 2b (`Payments`/`Refunds`), Plan 2 (`Events`, `EventPriceTiers`).

**Migration owner:** Agent B.

## Global Constraints

Same as the other M7 plans, copied so this stands alone.

- **Integer enums** (`Int @db.SmallInt` + code map) on new tables. `Invoices` keeps its string enums — it is an M4 table with live rows.
- **`bigint` keys, no `uuid`.** Public identity is `registration_code` / `attendee_code`.
- **FK actions:** `CASCADE` for owned children, `SET NULL` for pointers, `NO ACTION` everywhere else.
- **Every migration wrapped in `BEGIN;` … `COMMIT;`.**
- **`COMMENT ON` for every new table and column.**
- **Audit block on every new table**, with the at-most-one-actor `CHECK`.
- **Money** `Decimal(14,2)`; currency INR.
- Verify with the project's own commands: `npm run typecheck`, `npx vitest run`, `npm run lint`, `npx prisma migrate status`.

## Decisions already made by the client — do not re-open

No waitlist. No refund when a member cancels a paid seat; full refund when the association cancels the event. No substitute names. Expired membership keeps member pricing for `membership.grace_days`. Hold length is `event.payment_hold_days`; reminders are derived from it, not configured.

---

### Task 1: `GuestRegistrants`, and invoices billable to a guest

**Files:** `backend/prisma/schema/event.prisma`, `backend/prisma/schema/application.prisma`, `backend/prisma/schema/billing.prisma`, one migration.

- [ ] **Step 1: `GuestRegistrants`** — name, designation, company, email, phone, GST, PAN, full address, audit block. No `password_hash`, no `Users` row: a guest is a customer of one event, not an account.

- [ ] **Step 2: Make `Invoices` and `Payments` billable either way.** `member_id` becomes nullable, `guest_registrant_id` is added beside it, and a `CHECK` enforces exactly one:

```sql
CHECK (("member_id" IS NOT NULL) <> ("guest_registrant_id" IS NOT NULL))
```

That is the pattern `ApprovalRequests` and `AuthTokens` already use. Verify the CHECK passes on every existing row *before* the migration commits.

- [ ] **Step 3: Fix every read that assumed `member_id` is present.** `npm run typecheck` lists them. **Handle each one; never silence it with a cast.** This is the risk in this plan: guests never reach the member-scoped endpoints, but the type says the column may be null and each caller has to say what it does about that.

- [ ] **Step 4:** migrate, verify, comment check, full suite, commit.

---

### Task 2: `EventRegistrations`, `EventRegistrationAttendees`, `PaymentSubmissions`

**Files:** `backend/prisma/schema/event.prisma`, `backend/prisma/schema/billing.prisma`, one migration.

- [ ] **Step 1: The status codes**

| Code | Meaning |
|---|---|
| 0 | `PENDING_APPROVAL` — only when the event asks for approval |
| 1 | `PENDING_PAYMENT` |
| 2 | `PAYMENT_UNDER_VERIFICATION` |
| 3 | `CONFIRMED` |
| 4 | `EXPIRED` — the hold ran out |
| 5 | `CANCELLED` — by member or admin, no refund |
| 6 | `REJECTED` — approval refused |
| 7 | `REFUNDED` — the association cancelled the event |

- [ ] **Step 2: `EventRegistrations`** — event, nullable member, nullable user, nullable guest, `registrant_type`, `registration_code`, `price_tier_id`, subtotal/tax/total, `expires_at`, approval columns, terms acceptance, the billing snapshot, audit block.

Constraints: the member-or-guest `CHECK`; `status <> 6 OR rejection_reason IS NOT NULL`; `status NOT IN (0,1) OR expires_at IS NOT NULL`; and the partial unique index

```sql
UNIQUE (event_id, member_id) WHERE status IN (0,1,2,3) AND "deletedAt" IS NULL
```

so one live registration per company per event, while a re-booking after an expiry is still allowed.

- [ ] **Step 3: `EventRegistrationAttendees`** — one row per person: `attendee_code`, name, designation, email, phone snapshots, **`unit_price` frozen**, food preference, photo, ID, special requirement.

- [ ] **Step 4: `PaymentSubmissions`** — generic on `Invoices` so membership payments reuse it: method, reference, amount, paid-on, proof, status, rejection reason, verifier, `payment_id` set on verify. Partial unique: one PENDING per invoice.

- [ ] **Step 5:** migrate, prove the partial unique allows re-booking after EXPIRED, comment check, commit.

---

### Task 3: Holding seats without overselling

**Files:** `backend/src/modules/event/registration.repository.ts`, test.

- [ ] **Step 1: Write the failing test** — the guarded statement returns zero rows when the seats would exceed capacity.

- [ ] **Step 2: Implement one statement**

```sql
UPDATE "Events"
   SET seats_taken = seats_taken + $n
 WHERE id = $1
   AND status = 1
   AND (capacity IS NULL OR seats_taken + $n <= capacity)
RETURNING seats_taken;
```

Zero rows → not enough seats → the whole transaction rolls back and the booker is told **before** any invoice exists. Releasing is the same statement with `- $n`.

- [ ] **Step 3: Prove it under real concurrency.** Fire N simultaneous bookings at a 1-seat event against the real database and assert exactly one succeeds. This is the assertion the whole design exists for; a unit test with a mocked client cannot make it.

---

### Task 4: A member registers

- [ ] Attendee picker reads `MemberUsers` (Plan 1). Price resolved once via `resolveTier` + `audienceFor`, frozen per attendee.
- [ ] One transaction: seats → registration → attendee rows → invoice (unless free) → audit.
- [ ] Free event → `CONFIRMED` immediately, no invoice.
- [ ] Event asks for approval → `PENDING_APPROVAL`, **no invoice yet**, `expires_at` set on approval instead.
- [ ] Refusals: registration closed, sold out, already registered, no price today, membership check for member pricing.

---

### Task 5: Approval queue

- [ ] `GET /admin/events/registrations?status=0`, `POST …/approve`, `POST …/reject` (reason mandatory).
- [ ] Approve → `PENDING_PAYMENT`, invoice raised, **hold clock starts now** so an admin's delay never eats the payer's window.
- [ ] Reject → seats released at once, applicant emailed, no invoice ever existed.

---

### Task 6: Payment submission and verification

- [ ] Member/guest submits UTR + proof → `PAYMENT_UNDER_VERIFICATION`, **hold clock stops**.
- [ ] Admin queue: verify → `applyInvoicePayment` (writes `Payments` + `Receipts`) → `CONFIRMED`, each attendee emailed their own code. Reject → reason mandatory, seats stay held, payer may resubmit.

---

### Task 7: The hold-expiry and reminder job

- [ ] Nightly sweep over `status IN (0,1) AND expires_at < now()` → `EXPIRED`, seats released, payer told.
- [ ] Reminders on the days `reminderDaysFor(hold)` returns. Idempotent: a reminder is sent once per registration per day, so a double run cannot double-email.

---

### Task 8: Guest registration

- [ ] Public form: name, designation, company, email, mobile, address, city, state, pincode, GST. No login, ever.
- [ ] Members-only events refuse guests outright.
- [ ] Same seat-hold, invoice and verification path as a member.

---

### Task 9: Attendee list and export

- [ ] `GET /admin/events/:id/attendees` — **people, not companies**.
- [ ] Export matches the on-screen filter exactly. That is a definition-of-done item in M7, not a nicety.

---

### Task 10: Self-test suite additions

Extend the `event` suite, filling the skip it already carries:

- N concurrent registrations on a 1-seat event → exactly one CONFIRMED;
- registering twice → 409;
- registering past the deadline → 422 naming the date;
- a paid registration stays PENDING_PAYMENT until the invoice is PAID;
- approval-on: reject releases the seats and raises no invoice;
- an expired hold returns its seats.

---

## Self-review

**Spec coverage.** Design §4–§7 → Tasks 3–7. §8 members-only → Task 8. §9 grace → Task 4 (via `audienceFor`, already built). §10 rules table → Tasks 4–7. §15 registration fields → Tasks 2, 4, 8. Schema §3–§4 → Tasks 1–2.

**Biggest risk:** Task 1 Step 3. Making `Invoice.member_id` nullable changes a type every billing read depends on. The type-checker surfaces each one; the instruction is explicit that they be handled rather than cast away.

**Second risk:** Task 3. The concurrency assertion has to run against real Postgres. A mocked test proves nothing about a race.
