# Membership Purchase Flow — design spec

**Date:** 2026-09-07 · **Module:** M4 / M5 (approval, billing) · **Status:** draft, awaiting approval
**Depends on:** `2026-09-07-membership-fee-plans.md` (the plans themselves)
**Supersedes:** the plan-at-signup wiring shipped 2026-09-07 the same day.

---

## 1. The change in one sentence

Approval decides **eligibility**, the member decides **what they buy**, and payment makes them a
member — so the plan is chosen in the portal after approval, not on the signup form.

## 2. Why

Approval currently prices the membership, creates the term, raises the invoice and issues the
member code, all in one transaction. That forces three things that do not belong together:

1. **The applicant must commit to a price before knowing whether they are even eligible.** Their
   form takes twenty minutes and needs documents; discovering the fee at the end of it is how
   applications get abandoned.
2. **The reviewer is looking at money while assessing legitimacy.** "Is this a real lab-grown
   diamond company" and "what are they buying" are different questions, decided by different
   people.
3. **A member code is burned on someone who may never pay.** A member number means *in the
   register*; an approved applicant who never chooses a plan is not in it.

Separating them also deletes work rather than adding it: no plan step on the signup form, no
`?feePlan=` parameter, no blocked Submit.

## 3. The lifecycle

| Stage | Member status | Code | Term | Invoice | They see |
|---|---|---|---|---|---|
| Applied | `DRAFT` | — | — | — | Application status |
| Approved | `PENDING` | — | — | — | Guest + plan chooser |
| Plan chosen | `PENDING` | — | `PENDING_PAYMENT` | UNPAID | Guest + their invoice |
| Paid | `ACTIVE` | **issued** | `ACTIVE` | PAID | Everything |

The middle two states already exist in the data model. Nothing new is invented; what moves is
*when* each thing happens.

## 4. The flow

### 4.1 `/membership` — public price list

Informational only. Four cards showing the tax-inclusive joining price and the renewal price,
and one **Apply for membership** button. No plan picker: the visitor is reading, not buying.

### 4.2 `/signup` — company details and documents

No plan step, no price question. Creates the `Members` row as `DRAFT` (ADR-016) and the
application.

### 4.3 Approval — eligibility only

```
Member DRAFT -> PENDING
documents adopted
email: "Approved — sign in and choose your plan"

NO member code · NO term · NO invoice
```

The review screen shows no prices. Between approval and payment the company is referred to by its
**application number**, because it has no member number yet.

### 4.4 The guest state

An approved member who has not paid sees their own account and nothing that members pay for.

| Can see | Cannot see |
|---|---|
| Plan chooser | Member directory |
| Own profile, own documents | Member pricing on events |
| Own invoice, once raised | Anything else members pay for |
| Application status | |

The portal states plainly what is locked and what unlocks it — "the member directory and member
event pricing open once your first invoice is paid". A locked door with no sign reads as a broken
site.

### 4.5 Choosing a plan

One transaction: create the term (`PENDING_PAYMENT`, carrying `fee_plan_id`) and raise the
invoice. **`MembershipTerms.fee_plan_id` is where a member's plan is recorded, permanently** — it
is what M6 reads at renewal.

### 4.6 Changing plan

**Allowed until the invoice is paid; refused afterwards.**

An unpaid invoice is a quote, not a debt — nothing has been exchanged, and refusing the change
only means the member emails the office and an admin does it by hand. Once paid, money has moved
and a term has started: un-picking it means refunds and pro-rata, which is a decision rather than
a correction. The refusal names the renewal date so the member knows when they *can* change.

Changing cancels the old invoice and term and issues new ones.

### 4.7 Payment

One transaction: invoice `PAID`, term `ACTIVE`, member `PENDING -> ACTIVE`, `joined_on` set, and
**the member code is allocated here**. Nothing depended on the code existing earlier — the billing
module never references it, and codes come from a Postgres sequence that already has gaps.

## 5. Rules

| # | Rule |
|---|---|
| R-1 | Approval writes no money: no price resolution, no term, no invoice, no member code |
| R-2 | A member holds at most one live term; choosing again cancels the previous unpaid one |
| R-3 | Plan may be changed freely while the invoice is unpaid, never once it is paid or part-paid |
| R-4 | A plan retired after it was quoted still honours the invoice already raised |
| R-5 | Directory and member event pricing require `ACTIVE`, not merely a login |
| R-6 | The member code is allocated on first payment and never before |

## 6. What changes

### Backend
| File | Change |
|---|---|
| `application/activation.service.ts` | Split. Approval keeps the status change and document adoption; pricing, term, invoice and code allocation come out. |
| new `member/membership.service.ts` | `choosePlan()` -> term + invoice. `changePlan()` -> cancel + reissue, refused once paid. |
| `member/member.service.ts` | Payment handler also allocates the member code. |
| `auth/register.service.ts` | Remove `fee_plan_id` handling. |
| `application/application.repository.ts` | Remove `fee_plan` from the review detail. |
| Portal guards | Directory and member event pricing gate on `ACTIVE`. |
| new job | Reminder after 7 days: approved, no plan chosen. |

### Customer
| | |
|---|---|
| `/membership` | Becomes informational; one Apply button. |
| `/signup` | Remove `?feePlan=` and the plan payload. |
| new `/portal/choose-plan` | The chooser. |
| `MemberShell` | Guest state for approved-but-not-active. |

### Admin
| | |
|---|---|
| `applications/SnapshotPanel.tsx` | Remove the plan panel — there is no plan at approval. |
| `members/ProfileTab.tsx` | Unchanged; already reads the plan from the term. |
| new list | "Approved, no plan chosen", so nobody is forgotten. |

### Unchanged
The fee plans themselves, their pricing, versioning and the two scope buttons; the admin fee-plan
screens; `MembershipTerms.fee_plan_id`; `InvoiceItems.fee_plan_id`; the member detail plan panel.

### Becomes unused
`MembershipApplications.fee_plan_id` — nothing to record at application time. Kept as a column,
written by nothing.

## 7. Edge cases

| # | Situation | Behaviour |
|---|---|---|
| EC-1 | Approved, never chooses | Stays `PENDING`. Reminder at 7 days. Appears on the admin list. |
| EC-2 | Plan retired after quoting, before payment | Invoice stands. It was quoted to them (R-4). |
| EC-3 | No plans published when they log in | Guest state plus "plans are being finalised"; admin alerted |
| EC-4 | Changes plan after paying | Refused, renewal date named (R-3) |
| EC-5 | Part-paid invoice, wants to change | Refused — money has moved |
| EC-6 | Admin chooses on their behalf (phone-in) | Allowed from member detail |
| EC-7 | Two tabs, two plans chosen | Second wins, first invoice cancelled (R-2) |
| EC-8 | Application rejected | No member code was ever burned |
| EC-9 | Member code requested before payment | There is none; correspondence uses the application number |

## 8. Build order

| # | Step |
|---|---|
| 1 | Backend: split activation — approval stops pricing and stops issuing the code |
| 2 | Backend: `choosePlan` / `changePlan` — term + invoice, with R-3 |
| 3 | Backend: move member-code allocation into the payment handler |
| 4 | Customer: portal guest state + plan chooser |
| 5 | Customer: strip the plan wiring from signup and `/membership` |
| 6 | Admin: remove the plan panel, add the "approved, no plan" list |
| 7 | Reminder job |
| 8 | Tests + Sentinel suite |

Steps 1–3 are the work; 5 and 6 are mostly deletion.

## 9. Decisions taken

| # | Date | Decision |
|---|---|---|
| D-1 | 2026-09-07 | The plan is chosen **after** approval, in the portal — not on the signup form. |
| D-2 | 2026-09-07 | Approval writes no money at all: no term, no invoice, no member code. |
| D-3 | 2026-09-07 | The **member code is allocated on first payment**. A member number means *in the register*, and an approved applicant who never pays is not. |
| D-4 | 2026-09-07 | Plan is changeable while the invoice is unpaid, fixed once paid. |
| D-5 | 2026-09-07 | Approved-but-unpaid members get **guest access**: their own account, never member benefits. |

## 10. Open ambiguities

| # | Question | Blocks |
|---|---|---|
| A | Reminder cadence for an approved member who has not chosen — once at 7 days, or escalating? | The reminder job (step 7) |
| B | Is an approved-no-plan member ever closed off, or does that list grow forever? | Nothing today; it becomes an operations question |
| C | May an admin approve *and* choose a plan in one action for a phone-in applicant? Assumed yes, as two steps on the member detail screen. | Step 6 |
