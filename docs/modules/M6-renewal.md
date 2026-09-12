# M6 — Membership Renewal

**Status:** PENDING · **Migration owner:** Agent B · **Blocking OQ:** none — OQ-6 answered 2026-09-10 (see *Decided* below); only the per-plan renewal amounts remain (`client-decisions.md` A2), which blocks billing, not the build · **Depends on:** M4 (terms + invoices exist), M5 (payment flow), M2 fee plans (`MembershipTerms.fee_plan_id`)

Plain-English version with worked examples: `docs/renewal-module-summary.md`.

## Goal
Nobody lapses by accident. Terms, reminders and grace behaviour are explicit and visible on both sides.

## Agent B — backend + admin
- Migration (all commented):
  - `TermStatus.PAID_UPCOMING` — paid before the term's start date.
  - `RenewalReminders` — one row per `(term_id, reminder_code)`, DB-unique.
  - Partial unique on `MembershipTerms (member_id, valid_from) WHERE status <> 'CANCELLED'` — a second job run cannot create a second term or invoice. `CANCELLED` is excluded because a plan change before payment cancels and recreates a term with the same start date.
  - Seed setting `membership.renewal_notice_days` = `15`.
- `modules/renewal`:
  - **Renewal job (daily)** — terms ending within `renewal_notice_days`; price from the term's `fee_plan_id` (that plan's renewal price, live version on the renewal date); dates via `planTerm()` with the admin-selected `billing.renewal_basis`; new term starts the day after the old one ends; term + invoice in one transaction. No renewal price → skip that member and report, never a ₹0 invoice.
  - **Reminder job** — `T-15` (with invoice), `T-7`, `T-3`, `T-0` (on the expiry date, never a hardcoded 31 March).
  - **Payment hook** — paid before `valid_from` → `PAID_UPCOMING`; paid on/after → `ACTIVE`.
  - **Start-date step (midnight)** — `PAID_UPCOMING` → `ACTIVE`, previous term → `EXPIRED`, `Members.current_term_id` moved; one transaction (the one-active-per-member index requires the order).
  - **Expiry sweep** — grace (`membership.grace_days`) ended with no paid term → member `EXPIRED`, one notification.
- Admin screens A-20: due/grace/expired buckets; "Generate invoices" runs the renewal job now for members already inside the notice window (no early billing of anyone else). No per-member grace extension — grace is `membership.grace_days` only.

## Agent A — member side
- `/membership/me/term`, `/membership/me/renew`, term history.
- Customer screens C-18, C-23 + dashboard banner states: active · paid, renews on … · expiring soon · in grace · expired (each with the exact consequence spelled out).

## Contracts frozen
- **Term status machine:** `PENDING_PAYMENT` → (`PAID_UPCOMING` →) `ACTIVE` → `EXPIRED`; `CANCELLED` for voided terms.
- **Reminder codes:** `T-15`, `T-7`, `T-3`, `T-0`.
- **Grace rules:** `membership.grace_days` (30); member keeps full access during grace.
- **What expiry blocks:** directory listing and search, member event pricing. Portal login and own invoices stay open.
- **Pricing:** member's own plan renewal price; renewal basis from System Settings, applied from the next renewal if changed.

## Self-test
`renewal` suite:
- Term ending within the notice window appears in the correct bucket.
- Renewal creates a contiguous term (no gap/overlap) under both `term` and `financial_year`.
- Renewal is priced from the member's `fee_plan_id` (Monthly, Quarterly, Yearly), not a shared row.
- Financial year: a monthly/quarterly term crossing 31 March is cut at 31 March and prorated by whole months.
- Running the renewal job twice → one term, one invoice (constraint blocks the second).
- Plan change before payment → cancelled term + new term with the same start date is allowed.
- Duplicate reminder insert → constraint blocks.
- Paid before start → `PAID_UPCOMING`; start-date step flips it to `ACTIVE` and the old term to `EXPIRED`.
- Expiry sweep flips status and emits one notification.
- Renewing inside grace restores `ACTIVE` without a coverage gap.
- No renewal price on the plan → no invoice, member reported.

## Definition of done
- Jobs are idempotent and re-runnable (proved by running each twice — no duplicate terms, invoices, reminders or notifications).
- Every bucket count on the admin screen matches a single SQL query, not a client-side filter.
- Member banners state the consequence, not just the status.

## Decided (2026-09-10)
| Topic | Decision |
|---|---|
| Renewal invoice raised | 15 days before expiry (`renewal_notice_days`); with invoice due days 15 it falls due on the expiry date |
| Reminder schedule | 15, 7, 3 days before + on the expiry date |
| Paid before start | `PAID_UPCOMING`, activated on the start date |
| Renewal basis | Admin-selected in System Settings (`term` / `financial_year`) |
| Renewal price | Member's own fee plan renewal price |
| Short March term (monthly/quarterly, financial year) | Accepted |
| Grace length | `membership.grace_days` |
| Post-grace behaviour | Expire, not suspend |
| Auto vs manual | Invoice auto-generated, paid manually, never auto-charged |
| Member starts renewal early | No — Renew/Pay appears only once the job has raised the invoice |
| Plan switch at renewal | Allowed until the renewal invoice is paid (cancel + reissue, as at first purchase) |
| Admin "Generate invoices" | Runs the job now, only for members inside the notice window |
| Per-member grace extension | None — master setting only |
| Member doesn't want to renew | "I don't want to renew" button: renewal invoice cancelled, reminders stop, access to term end then grace and `EXPIRED`; "Renew after all" undoes it. Stored as `MembershipTerms.renewal_declined_at` |
| When the first term starts (2026-09-11) | On the **payment** day, not the approval day (industry standard; "Member since" = term start). On payment the first term is re-dated: `term` basis → from the payment day for the plan's cycle; `financial_year` → from the payment day, end stays 31 March as invoiced. Already-paid members are not re-dated. Renewals unchanged (start the day after the previous term ends) |

## Approval checklist
Renewal amount on each published plan (`client-decisions.md` A2).
