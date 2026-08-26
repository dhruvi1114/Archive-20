# Customer User Journeys

Format per master instructions §8: persona, goal, starting point, decisions, actions, system response, completion, failure/recovery.

---

## CJ-1 Discover → Sign up

**Persona** Owner of a lab-grown diamond unit, mobile, low patience.
**Goal** Get an account to apply for membership.
**Start** Public homepage or a WhatsApp link.
**Decisions** Apply now vs read about the federation first.
**Actions** Click "Apply for membership" → signup form (name, company, email, phone, password) → receive OTP → verify.
**System response** Account created (`PENDING_VERIFICATION` → `ACTIVE` after OTP), email sent, redirect to the application form with signup data pre-filled.
**Completion** Logged in, standing on step 1 of the application with 3 fields already filled.
**Failure/recovery** Email already registered → "This email already has an account" + Login and Forgot-password links. OTP expired → resend (throttled, countdown shown). Wrong OTP 5× → 15-min lock with the unlock time stated.

---

## CJ-2 Complete and submit the membership application

**Goal** Submit a complete application without a phone call.
**Start** Application stepper: 1 Company details · 2 Contact & address · 3 KYC documents · 4 Category & fee · 5 Review & submit.
**Decisions** Which membership category; which documents to upload now vs later.
**Actions** Fill each step (auto-save draft on blur), upload documents against a visible checklist, pick category (fee shown live), review a read-only summary, submit.
**System response** Completeness validated server-side; on success status `SUBMITTED`, timeline appears, confirmation email, admin queue notified.
**Completion** "Submitted on <date>. Under Document Verification. Typically 2 working days. We'll email you." — a tracker page, not a dead end.
**Failure/recovery** Missing required document → step 3 highlighted with exactly which type is missing. File too large/wrong type → inline message with the actual limit. Session lost mid-form → draft restored on next login ("We saved your progress").

---

## CJ-3 Track application / respond to a return

**Goal** Know where it stands; fix what's wrong without guessing.
**Start** Dashboard card "Your application — under review (stage 2 of 3)".
**Actions** Open the tracker (timeline: submitted → verified → committee → final, with dates). If returned: the admin's remarks are quoted verbatim at the top, the specific fields/documents needing change are marked, "Resubmit" is the only primary button.
**System response** Resubmission returns the application to the queue; timeline shows the correction round.
**Completion** Approved → "Approved! Pay ₹X by <date> to activate." Rejected → reason + contact.
**Failure/recovery** Nothing to do but wait is stated explicitly ("No action needed from you right now") — the most common support call is prevented by that one line.

---

## CJ-4 Pay the membership invoice

**Goal** Become an active member.
**Start** Approval email or dashboard "Payment due" card.
**Decisions** Pay online now vs bank transfer.
**Actions** Open invoice (line items, tax, total, due date, days remaining) → Pay online → gateway → return.
**System response** Payment verified server-side; invoice `PAID`; membership `ACTIVE`; receipt generated and emailed; member code issued; directory listing goes live.
**Completion** "You're an active member until <date>. Member ID LGDGF/2026/0042. Download receipt."
**Failure/recovery** Gateway failure → "Payment didn't go through. You have not been charged. Try again or pay by NEFT (details below)." Ambiguous/pending → "We're confirming with the bank; this page updates automatically" + no double-charge (the same invoice cannot start a second successful payment).

---

## CJ-5 Maintain profile & KYC

**Goal** Keep company details current; replace an expiring trade licence.
**Actions** Profile page split into "Editable now" and "Needs approval" (A-11). Non-critical edits save immediately with a toast. Critical edits open a change request with a clear notice: "Admin approval required — usually 1 working day. Your current details stay live until then."
**Completion** Toast + status chip on the requested field ("Change pending approval").
**Failure/recovery** Rejected change → remarks shown, original value retained, resubmit allowed.

---

## CJ-6 Renew membership

**Goal** Don't lapse.
**Start** Reminder email/WhatsApp at T-30/T-15/T-7 (OQ-6) or the dashboard banner "Membership expires in 21 days".
**Actions** "Renew now" → confirm details (pre-filled from the current term) → renewal invoice → pay.
**System response** New `MembershipTerms` row from the current expiry date (no lost days), invoice, payment, term active.
**Completion** "Renewed until <date>." Renewal history lists every past term.
**Failure/recovery** Expired within grace → banner turns amber: "Expired 4 days ago — renew within N days to keep your listing." After grace → red: "Membership expired. Renew to restore directory listing and event access."

---

## CJ-7 Browse and register for an event

**Goal** Attend a federation event.
**Actions** Public/member event list → detail (date, venue, fee, deadline, seats left) → Register → free: instant confirmation; paid: invoice → pay.
**System response** Registration code issued, confirmation email with calendar details, seat count decremented atomically.
**Completion** "You're registered. Registration ID EVT-2026-0117. Details emailed."
**Failure/recovery** Sold out → "Registration full" + waitlist if enabled. Already registered → shows existing registration instead of creating a duplicate. Deadline passed → button disabled with the reason and the date.

---

## CJ-8 Read notices & use the directory

**Goal** Stay informed; find other members.
**Actions** Bell badge → notice list (unread first) → detail with attachment. Directory: search by company/city/category, open a member card, contact details per visibility rules (OQ-7).
**Completion** Unread count drops; directory result shows verified members only.
**Failure/recovery** Empty search → "No members match 'xyz'. Try a company name or city." with filters reset link.

---

## Cross-journey rules

- The member dashboard is a **next-action list**, not statistics: what's pending on you, what's pending on us, what expires soon.
- Every email links straight to the relevant screen (deep link + login redirect preserved).
- No member screen ever shows an internal id, stage id, or workflow code.
