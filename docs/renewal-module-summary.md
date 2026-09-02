# Membership Renewal — Simple Summary

**Status:** planned, not built. Module M6.
Design detail will live in a spec; this page is the easy version.

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
| `billing.renewal_basis` | `financial_year` (everyone ends 31 March) or `term` (12 months from joining) | to confirm |
| `membership.grace_days` | How long after expiry the member keeps access | `30` |

**Fee Structures** — one row covers everybody. There is no category or tier on
the renewal fee, so every member pays the same:

```
Charged for     Renewal
Amount          ₹ (association to confirm)
Tax %           18
Term (months)   12
Effective from  2026-04-01
Live            yes
```

A category-specific price is still possible later — the resolver prefers a
category row over the association-wide one — but nothing needs configuring for
that today.

---

## The flow in 7 steps

1. **The job wakes up** and finds every term ending in 30 days.
2. **It prices first, before writing anything.** No renewal fee configured means
   the job stops and reports it — it never raises a ₹0 invoice.
3. **It creates the next term and its invoice.** The term starts the day after
   the old one ends, so no member loses a day. Status is `PENDING_PAYMENT`:
   billing someone does not make them a member, paying does.
4. **Four reminders go out** — 30, 15 and 3 days before, and one on the expiry
   date itself.
5. **Grace begins at expiry.** For `grace_days` the member keeps everything, but
   every screen tells them what has happened and what to do.
6. **The sweep job ends grace.** Status becomes `EXPIRED` and access closes.
7. **Whenever they pay,** the waiting term becomes `ACTIVE` and everything
   returns at once.

---

## Worked example — two members who joined differently

|  | **Shreeji Exports** | **Sunrise Foods** |
|---|---|---|
| Joined | 1 April 2026 | 12 September 2026 |
| First term | 1 Apr 26 → 31 Mar 27 | 12 Sep 26 → 31 Mar 27 |
| Length | 12 months | **7 months — prorated** |
| First invoice | ₹29,500 | **₹17,208.33** |

Sunrise's first invoice reads:

```
Membership — 7 months, pro-rata to 31 Mar 2027   ₹14,583.33
GST @ 18%                                         ₹2,625.00
                                                ────────────
                                                 ₹17,208.33
```

**Charged by whole months, not days** (decision 2026-08-21): joining on the 12th
and joining on the 28th of September both buy September. Simpler to explain, and
nobody argues about half a month.

Both terms now end **31 March 2027**. They are on the same cycle, and Sunrise's
short first term never repeats.

### 1 March 2027 — the renewal job runs

```
resolveFee(RENEWAL)            → ₹25,000 + 18% = ₹29,500 · 12 months
renewal_basis = financial_year → 1 Apr 2027 → 31 Mar 2028   (full year, no proration)

Term     1 Apr 2027 → 31 Mar 2028
Status   PENDING_PAYMENT
Invoice  INV/2027-28/00041   ₹29,500
```

Both members are billed the same ₹29,500. Sunrise's short year is behind them.

### The four reminders

| Date | Message |
|---|---|
| 1 Mar | Expires in 30 days — ₹29,500 due |
| 16 Mar | Expires in 15 days |
| 28 Mar | 3 days left |
| **31 Mar** | **Your membership ends today** |

The first three say *this is coming*. The fourth says *this is happening now*,
which is the one people act on.

Sunrise pays on 20 March. Shreeji ignores all four.

### 1 April — grace begins for Shreeji

Thirty days, from `membership.grace_days`.

**They keep everything:** still listed in the member directory, still on member
pricing for events, still able to log in and pay.

**But every screen says:**

```
⚠ Your membership expired on 31 March 2027.
  Renew by 30 April to keep your access.
  ₹29,500 outstanding.            [ Pay now ]
```

**Admin sees three buckets:**

```
Renewals
  Due soon    14      terms ending within 30 days
  In grace     3      ← Shreeji Exports · 9 days left · ₹29,500
  Expired      7      past grace
```

Every count comes from one SQL query, never a filter applied in the browser.

### 1 May — the sweep closes the door

Grace ended at midnight. Shreeji becomes `EXPIRED`. That single status change
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

### Whenever they pay

| Pays on | Result |
|---|---|
| 20 Mar | Term goes `ACTIVE` on 1 Apr. They never noticed. |
| 15 Apr — in grace | `ACTIVE` immediately. Never left the directory. |
| 10 May — expired | `ACTIVE` immediately. Back in the directory that moment. |

**The term is 1 Apr 2027 → 31 Mar 2028 whichever date they pay.** Paying late
does not shorten what they bought; it costs them time locked out.

---

## The two bases, compared

`billing.renewal_basis` decides when terms end. Both are supported by
`planTerm()`, which is already written.

| | `financial_year` | `term` |
|---|---|---|
| Sunrise's first term | 7 months, ₹17,208 | 12 months, ₹29,500 |
| Proration | Yes, on first terms only | **Never** |
| Renewal dates | Everyone on 31 March | Each member's own anniversary |
| Reminder cadence | One busy season a year | A steady trickle all year |
| Job runs | Meaningfully once a year | Daily |
| Matches GJEPC | Yes — their deadline is 30 April, which is 31 March + 30 days grace | No |

**The build is the same either way.** The job asks "which terms end in 30 days",
which is one query under both. The setting only decides what `valid_till` was
set to in the first place.

One thing to get right: write the fourth reminder as **"on the expiry date"**,
not as a hardcoded 31 March, or it breaks under `term`.

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
UNIQUE (member_id, term_type, valid_from)   -- one renewal invoice per term
UNIQUE (term_id, reminder_code)             -- one reminder per stage per term
```

A second run hits the constraint and does nothing. **The database enforces this,
not the code** — code can forget to check, a constraint cannot. Without the
first, a job that runs twice bills every member twice.

Two more rules, both borrowed from how activation already behaves:

- **Price before you write.** If no renewal fee is configured the job fails
  loudly and changes nothing. A ₹0 invoice raised because the price list was
  empty is far worse than a job that refused to run.
- **Tax per line, then summed.** Not tax on the invoice total — rounding the
  total instead disagrees with the lines by a paisa, often enough to matter to
  whoever reconciles the bank statement.

---

## What gets built

**Already built** — this is mostly wiring existing parts together:

| Piece | Where |
|---|---|
| Fee resolution, with a `RENEWAL` fee type | `masters.service.ts` → `resolveFee()` |
| Proration, months not days | `activation.service.ts` |
| Term date maths, both bases | `helpers/membershipTerm.ts` → `planTerm()` |
| `MembershipTerms` table, `TermType.RENEWAL` | schema, created in M4 |
| Invoice creation | `activation.service.ts` |
| Both settings | `helpers/settings.ts`, seeded |

**Left to build — five pieces:**

1. **The renewal job** — find terms ending soon, price, create term + invoice
2. **`RenewalReminders` table** and the reminder job
3. **The expiry sweep job** — grace ended, flip to `EXPIRED`
4. **Admin screen** — the three buckets, bulk invoice generation, extend grace
   with a reason
5. **Member dashboard banner** — active · expiring soon · in grace · expired,
   each stating the consequence rather than just the status

---

## Still to decide

1. **The renewal amount.** GST is 18%; the base figure is the association's to
   give. (`client-decisions.md` A2, still open.) Until it exists the fee row
   cannot be created — and the job will correctly refuse to run rather than
   bill anyone ₹0.
2. **Which basis** — everyone on 31 March, or each member's own anniversary?
   Neither blocks starting the build.

Answered already: reminders at 30, 15 and 3 days plus one on the expiry date ·
grace comes from the existing master setting · after grace the member is
`EXPIRED`, not suspended · the renewal invoice is generated automatically and
paid manually, never auto-charged.
