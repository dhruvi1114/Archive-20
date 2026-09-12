# Membership Renewal — Simple Summary

**Status:** planned, not built. Module M6.
Design detail will live in a spec; this page is the easy version.
**Decisions updated 2026-09-10:** 15-day renewal notice, reminders at 15/7/3/0,
new `PAID_UPCOMING` term status, price taken from the member's own fee plan.

**The one-line version:** nobody lapses by accident, and nobody has to remember
to chase them.

---

## What it is

A membership lasts a fixed period and then stops. Renewal is the machinery that
bills the member before it stops, reminds them, gives them a short grace period,
and finally closes their access if they never pay — all without an admin
clicking anything.

**It is not a payment feature.** Payments already work. Renewal decides *when* a
member is billed, *what* they are billed, and *what happens* when they don't pay.

| | Renewal (M6) | Payments (M5, built) |
|---|---|---|
| Answers | When is this member billed, and what if they don't pay? | Did the money arrive, and issue a receipt |
| Runs | On a schedule, unattended | When a person acts |
| Touches | Terms, reminders, member status | Invoices, payments, receipts |

---

## Configured once, in masters

**System Settings**

| Setting | Meaning | Current |
|---|---|---|
| `billing.renewal_basis` | `term` (fixed term from joining) or `financial_year` (everyone ends 31 March). Whichever the admin selects is what the job uses. | selectable |
| `membership.grace_days` | How long after expiry the member keeps access | `30` |
| `membership.renewal_notice_days` | How many days before expiry the renewal term and invoice are raised — **to add in M6** | `15` |
| Invoice due days | Days from invoice to due date | `15` |

With notice `15` and due days `15`, a renewal invoice is **due on the expiry
date itself** — the simplest thing to tell a member.

**Fee Plans** — the renewal price comes from the **member's own plan**, not one
shared row. Every term records the plan it was bought on
(`MembershipTerms.fee_plan_id`), and renewal charges that plan's renewal price
from the price list live on the renewal date:

```
FEE STRUCTURE  "Membership 2026"
├─ Monthly     join  ₹3,000   renewal  ₹2,500
├─ Quarterly   join  ₹8,000   renewal  ₹7,000
└─ Yearly      join ₹25,000   renewal ₹20,000      all + 18% GST
```

See `docs/specs/2026-09-07-membership-fee-plans.md` for plans, versioning and
which price changes reach existing members.

---

## The flow in 7 steps

1. **The job wakes up daily** and finds every term ending in
   `renewal_notice_days` (15) days.
2. **It prices first, before writing anything.** The member's plan has no
   renewal price means the job stops and reports it — it never raises a ₹0
   invoice.
3. **It creates the next term and its invoice** at the plan's renewal price. The
   term starts the day after the old one ends, so no member loses a day. Status
   is `PENDING_PAYMENT`: billing someone does not make them a member, paying
   does.
4. **Four reminders go out** — 15, 7 and 3 days before, and one on the expiry
   date itself.
5. **Member pays:**
   - **before the new term starts** → term becomes `PAID_UPCOMING`; a midnight
     step makes it `ACTIVE` (and the old term `EXPIRED`) on its start date.
   - **after it starts** (in grace or expired) → `ACTIVE` immediately.
6. **Unpaid at expiry — grace begins.** For `grace_days` the member keeps
   everything, but every screen tells them what has happened and what to do.
7. **The sweep job ends grace.** Member becomes `EXPIRED` and access closes. They
   can still log in and pay; paying makes them `ACTIVE` at once.

### Term status machine

```
PENDING_PAYMENT ──paid before start──▶ PAID_UPCOMING ──start date──▶ ACTIVE ──end──▶ EXPIRED
       │                                                             ▲
       └──────────────paid on/after start────────────────────────────┘
CANCELLED — voided (e.g. member changed plan before paying)
```

`PAID_UPCOMING` exists because the database allows only **one `ACTIVE` term per
member**. A member who pays early cannot have the new term go `ACTIVE` while the
old one is still running — without this status their paid term would sit as
`PENDING_PAYMENT` and admin would chase money already received.

---

## Worked example — Sunrise Foods, Yearly plan, joins 12 September 2026

Yearly plan: join ₹25,000, renewal ₹20,000, + 18% GST.

|  | **Fixed term from joining** | **Financial year (31 March)** |
|---|---|---|
| First term | 12 Sep 26 → 11 Sep 27 | 12 Sep 26 → 31 Mar 27 (**7 months, prorated**) |
| First invoice | ₹29,500 | ₹17,208.33 |
| Renewal term + invoice raised | 27 Aug 27 | 16 Mar 27 |
| Next term | 12 Sep 27 → 11 Sep 28 · ₹23,600 | 1 Apr 27 → 31 Mar 28 · ₹23,600 |
| Reminders | 27 Aug · 4 Sep · 8 Sep · 11 Sep | 16 Mar · 24 Mar · 28 Mar · 31 Mar |
| Grace | 12 Sep → 11 Oct 27 | 1 Apr → 30 Apr 27 |
| `EXPIRED` if unpaid | 12 Oct 27 | 1 May 27 |

Sunrise's prorated first invoice (financial year) reads:

```
Membership — 7 months, pro-rata to 31 Mar 2027   ₹14,583.33
GST @ 18%                                         ₹2,625.00
                                                ────────────
                                                 ₹17,208.33
```

**Charged by whole months, not days** (decision 2026-08-21): joining on the 12th
and joining on the 28th of September both buy September.

### The four reminders (financial year)

| Date | Message |
|---|---|
| 16 Mar | Renewal invoice raised — ₹23,600 due 31 March |
| 24 Mar | Expires in 7 days |
| 28 Mar | 3 days left |
| **31 Mar** | **Your membership ends today** |

### 1 April — grace begins if unpaid

Thirty days, from `membership.grace_days`.

**They keep everything:** still listed in the member directory, still on member
pricing for events, still able to log in and pay.

**But every screen says:**

```
⚠ Your membership expired on 31 March 2027.
  Renew by 30 April to keep your access.
  ₹23,600 outstanding.            [ Pay now ]
```

**Admin sees three buckets:**

```
Renewals
  Due soon    14      terms ending within the notice window
  In grace     3      ← Sunrise Foods · 9 days left · ₹23,600
  Expired      7      past grace
```

Every count comes from one SQL query, never a filter applied in the browser.

### 1 May — the sweep closes the door

Grace ended at midnight. The member becomes `EXPIRED`. That single status change
does all of this at once:

| | |
|---|---|
| ❌ | Disappears from every member's directory search |
| ❌ | Sees the "Renew" lock screen in the directory |
| ❌ | Loses member pricing on events |
| ✅ | **Can still log in and reach their own invoice** |

That last row is not optional. Lock an expired member out completely and they
cannot pay the invoice that would let them back in.

**Nobody clicked anything.** The job did it.

### Whenever they pay (financial year)

| Pays on | Result |
|---|---|
| 20 Mar | `PAID_UPCOMING`; goes `ACTIVE` on 1 Apr. They never noticed. |
| 15 Apr — in grace | `ACTIVE` immediately. Never left the directory. |
| 10 May — expired | `ACTIVE` immediately. Back in the directory that moment. |

**The term is 1 Apr 2027 → 31 Mar 2028 whichever date they pay.** Paying late
does not shorten what they bought; it costs them time locked out.

---

## Monthly and Quarterly plans under both bases

Same 7 steps, shorter terms. Joined 12 Sep 2026. Prices include 18% GST.

**Quarterly** (join ₹9,440, renewal ₹8,260)

| Term | Fixed term | Financial year |
|---|---|---|
| 1 (new) | 12 Sep → 11 Dec · ₹9,440 | 12 Sep → 11 Dec · ₹9,440 |
| 2 | 12 Dec → 11 Mar · ₹8,260 | 12 Dec → 11 Mar · ₹8,260 |
| 3 | 12 Mar → 11 Jun · ₹8,260 | 12 Mar → **31 Mar · ₹2,753.33** (1 of 3 months) |
| 4 | 12 Jun → 11 Sep · ₹8,260 | 1 Apr → 30 Jun · ₹8,260 |
| Then | every 3 months from the 12th | Apr–Jun, Jul–Sep, Oct–Dec, Jan–Mar |

**Monthly** (join ₹3,540, renewal ₹2,950)

| Term | Fixed term | Financial year |
|---|---|---|
| 1 (new) | 12 Sep → 11 Oct · ₹3,540 | 12 Sep → 11 Oct · ₹3,540 |
| 2–6 | 12th → 11th · ₹2,950 | same |
| 7 | 12 Mar → 11 Apr · ₹2,950 | 12 Mar → **31 Mar · full ₹2,950** (20 days) |
| Then | 12th → 11th | 1st → end of each calendar month |

Under financial year, the one term that would cross 31 March is cut short, and
from 1 April everyone is on the same calendar. **Accepted (2026-09-10).**
`planTerm()` only ever shortens a term, never extends one.

---

## The two bases, compared

`billing.renewal_basis` decides when terms end. Both are supported by
`planTerm()`, which is already written. The admin's selection in System Settings
is read each time a term is planned: **changing it later leaves existing terms
as they are and applies from the next renewal.**

| | `term` (fixed term) | `financial_year` |
|---|---|---|
| Proration | **Never** | Only on the term that would cross 31 March |
| Renewal dates | Each member's own anniversary | Everyone on 31 March (yearly plans) |
| Reminder cadence | A steady trickle all year | One busy season a year for yearly plans |
| Matches GJEPC | No | Yes — their deadline is 30 April, which is 31 March + 30 days grace |

**The build is the same either way.** The job asks "which terms end in 15 days",
which is one query under both. The setting only decides what `valid_till` was
set to in the first place.

Write the fourth reminder as **"on the expiry date"**, not as a hardcoded
31 March, or it breaks under `term`.

---

## What expiry actually blocks

| | Expired member |
|---|---|
| Listed in the member directory | **No** |
| Can search the member directory | **No** |
| Member pricing on events | **No** |
| Log in to the portal | **Yes** |
| See and pay their own invoices | **Yes** |

The directory half of this is already built and reads `Members.status` directly —
renewal is what *sets* that status, the directory is one of the things that
*reads* it.

---

## One setting, two meanings

`membership.grace_days` currently means *"how long you keep member pricing on
events"*. Renewal gives it a second job: *"how long before you are marked
expired"*.

**Decision: use one setting for both.** The same number is a sensible default,
and it keeps the configuration honest — one grace period, not two that can
silently disagree.

If the association ever wants them to differ — say, expire after 15 days but
keep event pricing for 30 — that is a second setting added later, not a rewrite.

---

## Safety rules

Both jobs run unattended, so both must be safe to run twice:

```sql
-- one live term per member per start date (CANCELLED ignored)
UNIQUE (member_id, valid_from) WHERE status <> 'CANCELLED'
-- one reminder per stage per term
UNIQUE (term_id, reminder_code)
```

A second run hits the constraint and does nothing. **The database enforces this,
not the code** — code can forget to check, a constraint cannot. Without the
first, a job that runs twice bills every member twice. Neither exists yet; both
come with the M6 migration.

`CANCELLED` is excluded on purpose: changing plan before paying cancels the old
term and creates a new one with the **same start date**. A plain unique would
block that.

Two more rules, both borrowed from how activation already behaves:

- **Price before you write.** If the member's plan has no renewal price the job
  fails loudly for that member and changes nothing. A ₹0 invoice is far worse
  than a job that refused to run.
- **Tax per line, then summed.** Not tax on the invoice total — rounding the
  total instead disagrees with the lines by a paisa, often enough to matter to
  whoever reconciles the bank statement.

---

## What gets built

**Already built** — this is mostly wiring existing parts together:

| Piece | Where |
|---|---|
| Fee plans with join + renewal price | `masters.feePlans.service.ts` |
| The member's plan on each term | `MembershipTerms.fee_plan_id` |
| Proration, months not days | `activation.service.ts` |
| Term date maths, both bases | `helpers/membershipTerm.ts` → `planTerm()` |
| `MembershipTerms` table, `TermType.RENEWAL`, one-active-per-member index | schema, created in M4 |
| Invoice creation | `activation.service.ts` |
| Renewal basis + grace settings | `helpers/settings.ts`, seeded |

**Left to build — seven pieces:**

1. **Migration** — `PAID_UPCOMING` term status, `RenewalReminders` table, both
   safety constraints, `membership.renewal_notice_days` setting (default 15)
2. **The renewal job** — find terms ending within the notice window, price from
   the member's plan, create term + invoice
3. **The reminder job** — 15 / 7 / 3 days before and on the expiry date
4. **The start-date step** — midnight: `PAID_UPCOMING` → `ACTIVE`, old term →
   `EXPIRED`, `Members.current_term_id` moved, in one transaction
5. **The expiry sweep job** — grace ended, member → `EXPIRED`
6. **Admin screen** — the three buckets, and "Generate invoices" which runs the
   renewal job now for members already inside the notice window
7. **Member dashboard banner** — active · paid, renews on … · expiring soon · in
   grace · expired, each stating the consequence rather than just the status

---

## Decided

| Topic | Decision |
|---|---|
| When the renewal invoice is raised | 15 days before expiry (was 30) — 2026-09-10 |
| Reminders | 15, 7, 3 days before + on the expiry date — 2026-09-10 |
| Paid before the new term starts | `PAID_UPCOMING`, activated on start date — 2026-09-10 |
| Renewal basis | Whatever the admin selects in System Settings — 2026-09-10 |
| Renewal price | The member's own plan's renewal price, live version — 2026-09-10 |
| Short March term (monthly/quarterly, financial year) | Accepted — 2026-09-10 |
| Grace length | From the existing `membership.grace_days` setting |
| After grace | Member `EXPIRED`, not suspended |
| Auto vs manual | Invoice generated automatically, paid manually, never auto-charged |
| Member starts renewal early | No — Renew/Pay appears only once the invoice is raised — 2026-09-10 |
| Plan switch at renewal | Allowed until the renewal invoice is paid (cancel + reissue) — 2026-09-10 |
| Admin "Generate invoices" | Runs the job now, only for members inside the notice window — 2026-09-10 |
| Per-member grace extension | None — `membership.grace_days` only — 2026-09-10 |
| Member doesn't want to renew | "I don't want to renew" button: invoice cancelled, reminders stop, access to term end, then grace and `EXPIRED`; can come back with "Renew after all" — 2026-09-10 |
| When the first term starts | On the payment day, not the approval day — approved 9 Sep, paid 10 Sep, monthly plan → 10 Sep to 9 Oct. Financial year: from the payment day to 31 March as invoiced. Already-paid members keep their dates — 2026-09-11 |

## Still to decide

1. **The renewal amounts** on each plan are the association's to give
   (`client-decisions.md` A2). Until a plan has one, the job correctly refuses
   to bill members on it.
