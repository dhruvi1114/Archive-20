# Screen Inventory

`M#` = module cycle · Owner A = customer/member workstream, B = admin workstream. States column lists the non-obvious ones each screen must implement beyond loading/success.

## Customer (Next.js) — Owner A

| # | Screen | M | Key states |
|---|---|---|---|
| C-01 | Home | M9 | — |
| C-02 | About | M9 | — |
| C-03 | Membership info (categories, fees) | M2/M9 | empty (no categories configured) |
| C-04 | Public events list / detail | M7/M9 | empty, past-event, registration-closed |
| C-05 | Public directory list / profile | M9 | empty search, hidden-fields notice |
| C-06 | Signup | M1 | duplicate email, weak password, rate-limited |
| C-07 | OTP verification | M1 | expired, wrong code, resend countdown, locked |
| C-08 | Login | M1 | wrong credentials, locked, unverified→resend |
| C-09 | Forgot / reset password | M1 | invalid or used token |
| C-10 | Member dashboard (next actions) | M3 | empty (nothing pending), blocked (application returned), payment due |
| C-11 | Application stepper (5 steps) | M4 | draft restored, per-step validation, autosave failed |
| C-12 | Application review & submit | M4 | incomplete blocking list |
| C-13 | Application tracker (timeline) | M4 | submitted, under review, returned (remarks), approved, rejected |
| C-14 | Document upload & checklist | M3/M4 | too large, wrong type, upload failed, verified, rejected+reason, re-upload |
| C-15 | Company profile (edit / needs-approval split) | M3 | pending-change chip, rejected change |
| C-16 | Contacts | M3 | last-contact-cannot-delete |
| C-17 | Addresses | M3 | empty |
| C-18 | Membership & term (`/application/membership`, no new nav item) | M6 | active, expiring soon, paid / renews on, in grace, declined, expired |
| C-19 | Invoice list | M5 | empty, overdue highlight |
| C-20 | Invoice detail + Pay | M5 | unpaid, partly paid, paid, cancelled, payment-in-progress |
| C-21 | Payment result (return from gateway) | M5 | success, failure, pending/unknown |
| C-22 | Payment history + receipts | M5 | empty |
| C-23 | Renewal confirm / plan switch (switch-plan section of C-18) | M6 | fee/plan changed since last term, claim pending, not on sale |
| C-24 | Events (member) + detail | M7 | full, deadline passed, already registered, member-only |
| C-25 | Event registration confirm / my registrations | M7 | pending payment, confirmed, cancelled |
| C-26 | Notices list / detail | M8 | empty, unread badge, attachment |
| C-27 | Notification feed | M8 | empty, unread grouping |
| C-28 | Directory (member view) | M9 | empty search |
| C-29 | Settings (password, contact, directory visibility) | M1/M9 | wrong current password |
| C-30 | 404 / 500 / offline / maintenance | M0 | — |

## Admin (React + Vite) — Owner B

| # | Screen | M | Key states |
|---|---|---|---|
| A-01 | Admin login | M1 | wrong credentials, locked, no-role account |
| A-02 | Work queue landing (permission-scoped) | M1/M4 | all-clear, per-queue empty, role-restricted |
| A-03 | Application queue | M4 | empty, filtered-empty, overdue-SLA badge |
| A-04 | Application review & decide | M4 | already-decided-by-other, missing fee config, remarks required |
| A-05 | Approval history timeline | M4 | — |
| A-06 | Profile change requests | M4 | empty, diff view |
| A-07 | Member list | M3 | empty, filtered-empty, export in progress |
| A-08 | Member detail (7 tabs) | M3 | suspended banner, unpaid-dues banner |
| A-09 | Member status change dialogs | M3 | reason required, unpaid-invoice warning |
| A-10 | Categories & tiers | M2 | in-use-cannot-delete |
| A-11 | Fee structures | M2 | overlapping-effective-date conflict |
| A-12 | Document types master | M2 | in-use-cannot-delete |
| A-13 | Document verification view | M3 | preview unavailable, reject reason required |
| A-14 | Invoice list (+ dues/overdue totals) | M5 | empty, filtered |
| A-15 | Invoice detail / create / issue / cancel | M4/M5 | immutable-after-issue, cancel confirmation |
| A-16 | Record offline payment | M5 | exceeds balance, duplicate reference |
| A-17 | Payments list | M5 | stuck/pending payments highlighted |
| A-18 | Reconciliation (CSV upload + match report) | M5 | parse error, unmatched rows |
| A-19 | Refunds (request / approve) | M5 | same-admin-cannot-approve, exceeds refundable |
| A-20 | Renewals (`/renewals`; Due Soon / In Grace / Expired tabs, counts from one SQL query) | M6 | empty tab, Generate Invoices result |
| A-21 | Event list / create / edit | M7 | publish confirmation with audience count |
| A-22 | Event registrations | M7 | capacity reached, waitlist |
| A-23 | Attendance check-in | M7 | already checked in, not found |
| A-24 | Attendee report / export | M7 | empty |
| A-25 | Notice composer + audience preview | M8 | audience = 0 blocks publish, scheduled |
| A-26 | Notice delivery report | M8 | failures + retry |
| A-27 | Notification templates | M8 | invalid placeholder |
| A-28 | Notification outbox | M8 | failed rows, retry, provider not configured (WhatsApp) |
| A-29 | Dashboard & reports | M10 | no data for range, export running |
| A-30 | Designations / committees / chapters | M10 | term overlap warning |
| A-31 | Roles & permission matrix | M10 | last-super-admin guard, role-in-use guard |
| A-32 | Admin users | M10 | deactivate self blocked |
| A-33 | Approval workflow (read-only) | M4 | — |
| A-34 | System settings | M10 | invalid value type |
| A-35 | Audit log | M10 | empty filter result |
| A-36 | 403 / 404 / 500 | M0 | — |

Two screens added by this review (`security.md` §8): **C-31 Privacy policy** and **C-32 Terms of use** (M9, static, content owner = client).

C-18 also renders as a renewal banner above every other member screen (M6, built).

**Totals:** 32 customer screens, 36 admin screens. Any screen not listed here does not get built without a scope change.
