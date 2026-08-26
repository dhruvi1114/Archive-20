# Decisions Needed from the Association

One page, plain language, for the Lab Grown Diamond Growers Federation. Engineering detail lives elsewhere; this is what only the client can answer.

Context from the signed proposal: the association nominates a single point of contact, provides content and data (member categories, fee structure, branding), and signs off within **five working days** of each milestone. Delays in these inputs shift the delivery schedule (Client Responsibilities clause).

---

## A. Needed before we build the membership catalogue (next cycle but one)

**A1. Membership categories and tiers.** What can a company apply for? Give the exact names as they should appear to applicants — e.g. "Grower", "Manufacturer", "Trader", and any tiers inside them (Gold / Silver, or Founder / Ordinary / Associate).

**A2. Fees.** For each category/tier: the amount in ₹, whether GST applies and at what rate, and the membership duration (12 months? financial year?).

**A3. Eligibility.** Anything that decides whether an applicant qualifies for a category — turnover, years in business, certifications, unit registration. If eligibility is judged manually by the committee rather than by rules, say so; that is a valid answer and simpler to build.

**A4. Required documents.** Which documents must an applicant upload, and which are mandatory versus optional? Our working list is GST certificate, IEC certificate, PAN, trade licence, and any accreditation certificates. Confirm or correct it.

**A5. Invoice format.** Does the association issue GST tax invoices? If yes: GSTIN, the invoice number format you need (e.g. `INV/2026-27/00001`), and the HSN/SAC code for membership fees.

---

## B. Needed before we build the approval workflow

**B1. Approval stages.** How many people review an application, in what order, and who are they by role? Our proposal is three stages: document verification (staff) → committee review → final approval (secretary/president). Confirm or replace.

**B2. Rejection versus return.** When an application is incomplete, should the reviewer be able to send it back for correction, or only approve/reject outright? Is there a limit on how many times an applicant may resubmit?

**B3. Who can approve.** Our default is that general admin staff *cannot* approve memberships — only committee/approver roles and the super admin can. Staff can return an application for correction. Is that how the federation works?

---

## C. Needed before we build billing and renewals

**C1. Payment gateway.** Which provider — Razorpay, PayU, CCAvenue, or another? The account is opened in the association's name (third-party costs are client-borne per the proposal). Until this is chosen, the platform records offline payments (NEFT, cheque, cash, UPI) and works fully.

**C2. Renewal rules.** When does membership expire — a fixed date each year, or 12 months from joining? How many reminders before expiry, and at what intervals? Is there a grace period after expiry, and what happens when it ends: does the member get suspended, hidden from the directory, or removed?

**C3. Refunds.** If a member is refunded, does their membership end, shorten, or continue unchanged? (Note: the proposal's "all payments are non-refundable" clause covers Sarvadhi's fees, not the association's own refunds to members.)

---

## D. Needed before the public site goes live

**D1. Member directory.** Should the directory be visible to the public, or only to logged-in members? Which fields may each audience see — company name, city, category, contact person, phone, email, website?

**D2. Public content.** Homepage and About copy, the association's logo and wordmark, office-bearer names and photographs if they should appear.

**D3. Privacy policy and terms of use.** Required for a platform holding company KYC data. The association owns this content; we place it.

---

## E. Communication

**E1. WhatsApp.** The proposal includes WhatsApp notices. That needs a WhatsApp Business API provider account in the association's name and pre-approved message templates. Until it exists, all notifications go by email and in-portal, and the WhatsApp channel stays switched off rather than half-built.

**E2. Sending email address.** Which address should platform emails come from (e.g. `noreply@lgdgf.org`)? We will need DNS records added so the mail is not marked as spam.

---

## F. Hosting and data

**F1. Hosting account.** Per the proposal, all member data resides on the association's own hosting or cloud account. Which provider, and who holds the account? We deploy into it.

**F2. Backup destination.** Backups must be copied somewhere off the server — a second cloud bucket or storage account. Who owns it and holds the credentials?

**F3. Data retention.** How long should we keep documents belonging to applicants who were rejected or withdrew? And how long should the audit trail of approvals and financial actions be retained? (Seven years is common for financial records in India.)

---

## G. Two things to confirm in writing

**G1. Accounting integration is deferred.** The signed proposal includes two-way sync of invoices and payments with accounting software (Refrens / Vyapar / Zoho Books, and Tally / QuickBooks referenced elsewhere). This has been **parked for the current build** at the client's instruction. It is not cancelled — it is deferred, and the proposal's Change Requests clause means the deferral should be confirmed in writing so nobody later reads the delivery as incomplete. Suggested wording:

> "Accounting integration as described in the proposal (two-way invoice and payment sync with cloud accounting platforms) is deferred out of the current delivery by agreement. It remains available and will be scoped and scheduled separately when the association is ready. All other proposal scope is unaffected."

**G2. Existing member data.** The proposal includes basic import of existing records. Does the association have current members in a spreadsheet that should be loaded into the platform at launch? If yes, roughly how many, and can we see the file's columns?

---

## What we are NOT waiting on

These are already handled and need no decision now: payment gateway choice (offline payments work meanwhile), WhatsApp provider (email works meanwhile), hosting choice (development runs locally). They only become blocking near go-live.
