# Event Module — Design Summary (M7)

**Date:** 2026-08-26 · **Status:** Approved in brainstorming, ready for implementation plan
**Scope now:** create/edit event · who is attending · member & non-member pricing · payment verification
**Not in scope:** attendance / check-in on event day · accounting integration
**Built together with:** company team logins (Member module) — events depend on them

---

## 1. The three settings

Admin changes these without a code release. Stored in the existing `Settings` table.

| Key | Value | Meaning |
|---|---|---|
| `event.payment_hold_days` | 5 | How long seats stay held without payment |
| `membership.grace_days` | 30 | How long an expired member keeps the member price |

**Reminders are not a separate setting.** They are derived from the hold period, so changing one number can never leave the two out of step:

```
first reminder  = day ceil(hold_days / 2)
final reminder  = day hold_days - 1
(duplicates dropped; if hold_days <= 2, only the final reminder is sent)
```

| hold_days | reminders sent on |
|---|---|
| 5 | day 3, day 4 |
| 7 | day 4, day 6 |
| 3 | day 2 |
| 2 | day 1 |

---

## 2. Company team logins

One membership, many logins.

```
ABC Pvt Ltd — Member #1042 — valid till 31 Mar 2027
├── Ramesh  (Owner)
├── Priya   (Team member)
└── Anil    (Team member)
```

**Steps:** Owner → Company Profile → Team → Add member (name, designation, email)
→ invite email → invitee sets own password → logs in as themselves.

Exact role permissions are **parked** and decided at the end of the module.

---

## 3. Admin creates an event

**Step 1 — Fill the form (A-21)**

- Basic: title, description, banner, category
- Where: venue name, address 1 & 2, **city**, **state**, **pincode**, map link
- When: date, start time, end time
- Who can join: **Members only** (invisible to public) or **Public** (members + non-members)
- Registration: opens on, closes on, capacity
- **☐ Registrations need admin approval before payment** (default OFF)
- **Collect from each delegate:** ☑ Food preference · ☐ Photo for badge · ☐ Government ID (see section 15)
- Price table (below)

**Step 2 — Price tiers.** One row per date range, two prices per row.

| Tier | From | To | Member | Non-member |
|---|---|---|---|---|
| Early bird | 01 Sep | 15 Nov | ₹1,000 | ₹2,000 |
| Regular | 16 Nov | 05 Dec | ₹1,500 | ₹2,500 |
| Late | 06 Dec | 10 Dec | ₹2,000 | ₹3,000 |

A free event is one row at ₹0. A tier runs to the **end** of its last day.

**Step 3 — Save** → `DRAFT`, nobody can see it.

**Step 4 — Publish** → confirmation states the audience size → `PUBLISHED` → live.

---

## 4. A member registers

1. Any team member opens the event and clicks **Register**.
2. Picker lists the company's team; tick the people going. Total updates live.
3. Confirm → **in one transaction**: seats deducted, registration created, one attendee row per person with the **price frozen on it**, invoice raised, `expires_at = now + payment_hold_days`.
4. Seats are held immediately. Next status depends on the event's approval checkbox:
   - **OFF** → **PENDING_PAYMENT**, invoice sent at once.
   - **ON** → **PENDING_APPROVAL**, no invoice yet (see section 5).
5. Screen shows either the bank details + hold deadline, or "Waiting for admin approval".

**Price rule:** the tier is chosen by the **registration date**, never the payment date.

---

## 5. Admin approval (only when the checkbox is ON)

Used for AGMs, committee meetings, limited delegations — anything the association vets.

1. Registration sits at **PENDING_APPROVAL** in the admin queue "Registration requests". Seats are already held.
2. Admin decides:
   - **Approve** → **PENDING_PAYMENT**, invoice raised, and **the hold clock starts now** (not at registration, so admin delay never eats the payer's time).
   - **Reject** → reason mandatory → seats released immediately → applicant emailed with the reason. No invoice ever existed, so no money to reverse.
3. If approval is granted after the price tier changed, the price is still the one frozen **at registration time**.
4. Approval-ON + free event → approve goes straight to **CONFIRMED**, no invoice.

---

## 6. Payment verification (replaces a payment gateway)

1. Payer transfers money, clicks **"I have paid"**, enters **UTR** and uploads the receipt.
2. Status **PAYMENT_UNDER_VERIFICATION** — the hold clock **stops** here.
3. Admin queue "Payments to verify":
   - **Verify** → invoice PAID → registration **CONFIRMED** → every attendee gets their own email and their own code.
   - **Reject** → reason mandatory → payer notified → seats stay held → payer re-submits.
4. Cash at the office: admin records the payment directly. Same result.
5. **Free event:** no invoice, no queue → **CONFIRMED** instantly.

Built behind the existing payment-provider interface (A-5), so adding Razorpay later changes no screens.

---

## 7. Nobody pays

With `event.payment_hold_days = 5`:

| Day | Action |
|---|---|
| 0 | Seats held, invoice sent |
| 3 | Reminder — "Pay within 2 days or your seats are released" |
| 4 | Final reminder |
| 5 | Auto-cancel, seats released, payer notified |

Change the hold to 7 days and the reminders move to days 4 and 6 on their own.

Re-booking later is priced at the **then-current** tier. A nightly job does the sweep.

---

## 8. A non-member registers (public events only)

1. Finds the event on the public site. **No login.**
2. Sees the non-member price for today's tier.
3. Guest form: name, designation, company, email, mobile, address 1 & 2, city, state, pincode, GST.
4. Seats held, invoice raised, same 5-day hold, same verification flow.
5. Confirmed → own email + own code. **Never receives a login.**

---

## 9. Expired membership — grace period

Membership ended 31 Mar 2027, `membership.grace_days = 30`:

| Booking date | Price | Message shown |
|---|---|---|
| Day 1–30 | Member | "Your membership expired on 31 Mar. Renew within N days to keep member pricing." |
| Day 31+ | Non-member | "Renew to pay the member price instead." |

---

## 10. Rules table

| Situation | Result |
|---|---|
| 2 seats left, 3 wanted | Whole booking fails. No partial booking. |
| Event full | **"Sold out."** No waitlist. |
| Many people grab the last seat at once | Seats counted inside the DB transaction — exactly one wins; others are told **before** paying. |
| Same company registers twice | Blocked. They edit the existing registration. |
| Admin rejects a registration request | Reason mandatory, seats released at once, applicant emailed. No invoice existed. |
| Admin is slow to approve | Hold clock starts at approval, so the payer always gets the full window. |
| Adding a person later | Priced at **today's** tier → top-up invoice. Existing attendees keep their old price. |
| Cancel **before** paying | Free. Seats released. |
| Cancel **after** paying | Allowed, seat released, **no refund**. Button warns clearly. |
| Sending a substitute person | **Not allowed.** The booked name is final. |
| Registering after the close date | Rejected, with the date shown. |
| Admin edits prices after bookings | Only future bookings change. |
| Admin changes date or venue | Allowed; everyone registered is emailed automatically. |
| Admin cuts capacity below bookings | Blocked, with the booked count shown. |
| **Admin cancels the event** | Blocked until **Refund all** is confirmed; then all paid registrations are refunded and everyone is emailed. |
| Attendee list / export | Lists **people, not companies**; export matches the on-screen filter. |
| Day-of attendance | **Not in this phase.** Design leaves room to add it later with no rework. |

---

## 11. Statuses

```
EVENT:   DRAFT → PUBLISHED → CANCELLED (refund all)

REGISTRATION (approval checkbox ON only):
   PENDING_APPROVAL ──approve──► PENDING_PAYMENT   (hold clock starts here)
                    └─reject─► REJECTED (seats released)

REGISTRATION:
   PENDING_PAYMENT ──pays──► PAYMENT_UNDER_VERIFICATION
        │                          ├─ verified ─► CONFIRMED
        │ hold expires             └─ rejected ─► back to PENDING_PAYMENT
        ▼
     EXPIRED (seats released)

   CONFIRMED ──member cancels──► CANCELLED (no refund)
   CONFIRMED ──event cancelled──► REFUNDED
```

---

## 12. What gets built

**New tables**
`EventPriceTiers` · `EventRegistrationAttendees` · `GuestRegistrants` · `MemberTeamInvites`

**Changed tables**
- `Events` — visibility, venue address fields, `registration_opens_at`, `requires_approval` (default false)
- `EventRegistrations` — nullable `member_id`, `registrant_type`, `expires_at`, `payment_reference`, `payment_proof`, `approved_at`, `approved_by`, `rejection_reason`; status enum gains `PENDING_APPROVAL`, `REJECTED`
- `Users` — multiple logins per member + invite flow
- `Settings` — the three keys in section 1

**Dropped for now** — `EventAttendance` / check-in

**Background job** — nightly hold-expiry and reminder sweep

**Non-negotiables**
- Capacity enforced in SQL **inside** the transaction, never read-then-write.
- Registration, attendee rows and invoice created **atomically**.
- Price frozen per attendee at registration time.
- Member-only events invisible to the public, not merely blocked.

---

## 13. Still open

- Exact team-member permissions (deliberately parked until the end of the module).
- Whether the association wants delegate fields beyond section 15 — nature of business, product category, chapter/region, sponsor interest, accommodation assistance. To be raised in `client-decisions.md`.

---

## 14. Worked example — end to end

**Cast:** Neha (admin) · ABC Pvt Ltd (member #1042 — Ramesh Owner, Priya, Anil) · Suresh of XYZ Traders (non-member).

### Setup — ABC builds its team

Ramesh → Company Profile → Team → Add member (Priya, Manager, priya@abc.com) → invite email → Priya sets her own password and logs in as herself. Same for Anil.

```
ABC Pvt Ltd — Member #1042 — valid till 31 Mar 2027
├── Ramesh (Owner) · Priya (Team) · Anil (Team)
```

### Neha creates the event

Title, banner · venue + address, city, state, pincode · date & time · Members only / Public · registration opens & closes · capacity · **☐ Registrations need my approval before payment** · the price table.
Save → `DRAFT` → **Publish** (confirmation states the audience size) → `PUBLISHED`.

---

### FLOW A — checkbox OFF · "Export Summit 2026", 100 seats

1. **10 Nov**, Priya opens the event: *Members ₹1,000 · early bird ends in 5 days · 63 available · 4 awaiting payment.*
2. **Register** → picker → ☑ Ramesh ☑ Priya ☑ Anil → total **₹3,000**.
3. **Confirm** — one transaction: seats 63 → **60 held** · 3 attendee rows with **₹1,000 frozen on each** · invoice INV-2291 · `PENDING_PAYMENT` · expires in 5 days.
4. Screen shows bank details, reference INV-2291, "held until 15 Nov".
5. Ramesh pays by NEFT → **"I have paid"** → enters UTR + uploads receipt → `PAYMENT_UNDER_VERIFICATION`. **The hold clock stops here.**
6. Neha's *Payments to verify* queue → checks the bank statement:
   - **Verify** → invoice PAID → `CONFIRMED` → Ramesh, Priya and Anil each get their own email with their own code.
   - **Reject** → reason mandatory → seats stay held → ABC re-submits.

**If nobody pays:** reminder day 3 · final reminder day 4 · auto-cancel day 5 · seats released · ABC emailed. Re-booking later pays the then-current tier.

---

### FLOW B — checkbox ON · "AGM 2026", members only, 200 seats

1. Priya registers 2 people. Seats held **immediately** (200 → 198).
2. Status `PENDING_APPROVAL`, **no invoice yet**. Screen: *"Your request is with the association. You will be told once it is approved."*
3. It appears in Neha's **Registration requests** queue.
4. **Neha approves** →
   - status → `PENDING_PAYMENT`, invoice raised now
   - **the 5-day hold clock starts at approval** — if Neha took 3 days, ABC still gets its full 5 days
   - the price is still the one **frozen at registration**, even if the tier has changed since
   - from here, identical to Flow A: pay → UTR → verify → `CONFIRMED`
5. **Neha rejects** →
   - reason mandatory ("This AGM is for Executive Committee members only")
   - seats released at once (198 → 200)
   - ABC emailed with the reason
   - **no invoice ever existed, so there is no money to reverse** — this is exactly why approval sits *before* payment

**Free event + approval ON:** approving goes straight to `CONFIRMED`, no invoice at all.

---

### Non-member Suresh — public event, 20 Nov

No login → sees **₹2,500** (non-member, Regular tier) → fills name, designation, company, email, mobile, address 1 & 2, city, state, pincode, GST → seats held → then follows whichever flow that event uses (A or B) → confirmed → his own email and code. **Never receives a login.**

---

### Expired membership

ABC's membership ended 31 Mar 2027, `membership.grace_days = 30`:

| Books on | Pays | Message |
|---|---|---|
| Day 1–30 | **₹1,000** member | "Expired on 31 Mar. Renew within N days to keep member pricing." |
| Day 31+ | **₹2,000** non-member | "Renew to pay the member price." |


---

## 15. Registration fields

Modelled on standard Indian association / export-council event forms. Members see everything pre-filled; non-members type it.

### A. Booking level — asked once per registration

| Field | Member | Non-member | Why |
|---|---|---|---|
| Registration type | auto | auto | Decides the price column |
| Membership number | auto 🔒 | — | Proof of the member rate |
| Company / organisation name | pre-filled 🔒 | required | Invoice |
| GST number | pre-filled 🔒 | required | Invoice, input credit |
| PAN | pre-filled ✏️ | optional | TDS cases |
| IEC code | pre-filled ✏️ | optional | Export-council events |
| Billing address 1 & 2, city, state, pincode, country | pre-filled ✏️ | required | Invoice |
| Contact person — name, email, mobile | pre-filled ✏️ | required | All correspondence about this booking |
| Number of delegates | from the picker | typed | Seats and amount |

🔒 = read-only, because [A-11](../../assumptions.md) requires admin approval to change KYC-critical fields (company name, IEC, GST, trade licence). The form links to Company Profile instead.

### B. Per delegate

| Field | Required | Why |
|---|---|---|
| Full name (as on ID) | Yes | Badge and entry list |
| Designation | Yes | Badge |
| Email | Yes | Their own confirmation and code |
| Mobile | Yes | Day-of contact |
| Food preference — Veg / Non-veg / Jain | Toggle (default ON) | Catering count |
| Photo | Toggle (default OFF) | Printed badges at larger events |
| Government ID type + number | Toggle (default OFF) | Venue security at expos |
| Special requirement / accessibility | Optional, always shown | Wheelchair, dietary, interpreter |

### C. Consent — mandatory

```
☑ I have read and accept the terms and the cancellation policy.
   I understand that once paid, the fee is NON-REFUNDABLE.
☐ I consent to photographs and video taken at this event being used
   by the association.
```

The first box must be ticked before Confirm. Store the timestamp and the policy version — this is what protects the association in a refund dispute, given the no-refund rule in section 10.

### D. Per-event toggles (decided)

Delegate fields are **not** hardcoded. The create-event form carries three switches — food preference, photo, government ID — so a one-hour members' meeting collects nothing extra while a two-day expo collects all three. Same form, admin-controlled.

### Pre-fill and snapshot rule

1. Everything a member already has is **pre-filled**.
2. KYC-critical fields are **locked**; the rest are **editable**.
3. **Editing on the event form changes only this registration — never the company profile.** Name, designation, email, phone and price are frozen onto the attendee row, so an old attendee report still shows what was true then.
4. Non-members get nothing pre-filled; their data is stored as a `GuestRegistrant`.

**Schema impact:** `EventRegistrations` gains the booking-level snapshot fields and `terms_accepted_at` / `terms_version`; `EventRegistrationAttendees` gains `food_preference`, `photo_path`, `id_type`, `id_number`, `special_requirement`; `Events` gains `collect_food_preference`, `collect_photo`, `collect_gov_id`.
