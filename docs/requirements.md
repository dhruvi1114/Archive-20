# Requirements — Association Management Platform (LGDGF)

Source of truth: `proposal.pdf` (Aug 7, 2026), `module-breakdown.docx`, `master-instructions-greenfield-association-platform.docx`, `CLAUDE.md`.

> **Verified 2026-08-12** against `docs/proposal.txt` (full text, supplied by the user). Feature coverage matches; the proposal additionally carries commercial and operational terms now captured in FR-22 and §3b — see `proposal-verification.md` §1b.

## 1. Business goal

Replace spreadsheets, manual approvals and WhatsApp follow-ups for the Lab Grown Diamond Growers Federation with one platform covering: membership application → approval → active membership → invoicing → payment → renewal, plus events, communication and a member directory.

## 2. Actors

| Actor | Portal | Description |
|---|---|---|
| Visitor | Public site (Next.js) | Browses association info, public events, public directory; starts an application |
| Applicant | Customer portal | Registered user with an in-flight membership application |
| Member | Customer portal | Approved member; pays invoices, renews, registers for events, appears in directory |
| Super Admin | Admin portal | Full access incl. RBAC, masters, workflow config |
| Admin | Admin portal | Day-to-day operations: members, applications, events, communication |
| Committee / Approver | Admin portal | Acts only on approval queues assigned to their stage |
| Accounts | Admin portal | Invoices, payments, refunds, reconciliation, financial reports |

## 3. Functional requirements by module

### FR-1 Public Website
Homepage/About, public event listing + event detail, public member directory (toggleable), application entry point, login/signup.

### FR-2 Authentication & Account
Member signup (email + password + OTP verification), member login, admin login (separate credential space), logout, session/token management, password reset, account activation/deactivation, role-based access for admin users.

### FR-3 Membership Application
Member: create/complete application, submit company + industry info, upload required documents, submit, track status, receive status-change notifications, respond to a "returned for correction" request.
Admin: list/review applications, view documents, approve/reject with remarks, move through configured stages.

### FR-4 Approval Workflow
Configurable multi-stage flow; stage configuration; approver assignment by role; queue per approver; approve/reject/return actions; remarks; full history; role-restricted queues; only valid status transitions permitted.

### FR-5 Member Profile & KYC
Company details, contacts, IEC code, GST, trade licence, certification/accreditation status, KYC document upload, document verification status, re-upload, profile update requests that require admin approval.

### FR-6 Membership Category / Tier
CRUD categories and tiers; assign category/tier to members; fee mapping per category/tier/duration. *(Actual category names, tiers, fees and eligibility rules are NOT in the proposal — see `assumptions.md` OQ-2.)*

### FR-7 Member Management
Listing, search, filter; application review; approve/reject; category/tier change; profile edit; suspend; reactivate; status + history view.

### FR-8 Billing & Finance
Member: view invoices, pay online, download receipt, payment history.
Admin: generate/track invoices, dues + overdue visibility, fee configuration, refunds, gateway reconciliation.

### FR-9 Payment Gateway
Initiate payment, handle success/failure, record transaction, update invoice status, generate receipt, reconcile. *(Provider not specified — OQ-4.)*

### FR-10 Membership Renewal
Expiry visibility, renewal initiation, renewal invoice, online renewal payment, renewal history, automated reminders. *(Reminder schedule, grace period, expiry behaviour — OQ-6.)*

### FR-11 Event Management
Admin: create/manage events, details/date/venue, free or paid, registration management, attendance tracking, attendee reports.
Member: browse, view, register, pay for paid events, receive confirmation.

### FR-12 Communication
Notices and circulars; broadcast to all; target by category/tier/filter; in-portal, email and WhatsApp delivery. *(WhatsApp provider/templates — OQ-5.)*

### FR-13 Member Directory
Searchable directory of approved members; search + filter; company info; association-controlled public visibility.

### FR-14 RBAC & Permissions
Roles: Super Admin, Admin, Committee/Approver, Accounts. Module+action permission mapping, enforced in the backend. *(Detailed matrix not in proposal — proposed matrix in `rbac.md`, needs sign-off, OQ-1.)*

### FR-15 Hierarchy & Designations
Office-bearer positions (President, Secretary, …), committee structure, chapter heads, designation setup, role mapping.

### FR-16 Accounting Integration — **PARKED (deferred contractual scope, not descoped)**
The proposal *does* include it: Admin Portal item 5 promises "two-way sync with cloud accounting platforms such as Refrens, Vyapar, Zoho Books for every invoice and payment", and the overview promises flow into "Tally / Zoho Books / QuickBooks". `CLAUDE.md` and master instructions §19 park it for the MVP.
Therefore: **no code, no schema, no stubs now** — and the client must be told in writing that it is deferred, under the proposal's own Change Requests clause. Otherwise delivery reads as incomplete against the signed scope. Tracked as PV-4.

### FR-17 Dashboard & Reports
Total members, pending approvals, revenue collected, renewals due, event statistics, exportable reports (CSV/XLSX).

### FR-18 Notifications & Automation
Application status, payment/invoice, renewal reminders, event registration, notices/circulars; email, WhatsApp, in-portal channels; templated; queued and retryable.

### FR-19 Document / File Management
KYC + industry document upload, document type + metadata, view/download, verification status, re-upload, backend-enforced access control.

### FR-20 Audit / Activity History (recommended, adopted)
User/admin action history, approval history, member status changes, financial action history, actor + timestamp + before/after.

### FR-22 Responsive Member Portal (contractual)
The proposal commits the Member Portal to full functionality across desktop, tablet and mobile browsers ("This is web responsiveness, not a native mobile app"). Every customer screen must work at 375 / 768 / 1280 px. Admin Portal carries no such commitment (targets ≥1280 with a usable ≥768 fallback).

### FR-21 System Configuration / Masters (recommended, adopted)
Categories, tiers, fee structures, approval workflows, designations, event config, document types, notification templates, system settings.

## 3b. Non-functional / contractual requirements (from the proposal)

| ID | Requirement | Source |
|---|---|---|
| NFR-1 | Data and member records belong to the client and **reside on the client's own hosting/cloud account**; Sarvadhi accesses only as required for implementation and support | Data Ownership clause |
| NFR-2 | Source code remains with Sarvadhi; the client receives the deployed solution | Intellectual Property clause |
| NFR-3 | 3 months complimentary support post go-live; defects in delivered scope fixed at no cost within that window | Support Period + Warranty |
| NFR-4 | Support Mon–Sat 10:00–19:00 IST via email and WhatsApp, first response ≤8 working hours | Support clause |
| NFR-5 | Warranty excludes client-side infrastructure, third-party integrations and unauthorised modification | Warranty clause |
| NFR-6 | Client provides content/data (categories, fee structure, branding) and signs off within 5 working days per milestone; delays shift the schedule | Client Responsibilities |
| NFR-7 | Third-party costs (gateway, WhatsApp API, accounting software, hosting, domain, SSL) are client-borne — we integrate, we do not procure | Third-Party Costs |
| NFR-8 | "Basic import" of legacy member data is inside scope; anything beyond it is not | Out of Scope wording |

## 4. Cross-cutting requirements (from master instructions + user direction)

| ID | Requirement |
|---|---|
| XC-1 | All request payloads and response `data` encrypted (AES-256-CBC + gzip), same scheme as Elvee |
| XC-2 | All user-facing messages via i18n (`i18n` package, `src/locales/<lang>.json`), no hardcoded strings |
| XC-3 | Layered backend: Route → Middleware → Validation → Controller → Service → Repository → Prisma |
| XC-4 | Prisma migrations only; never edit an applied migration; no `db push` against shared DBs |
| XC-5 | Money as `Decimal(14,2)`; never float |
| XC-6 | Backend is the sole authority for authz; a hidden frontend button is not a security boundary |
| XC-7 | Every module ends with a Sentinel self-test run before it can be marked done |
| XC-8 | Every screen handles loading / empty / success / error / disabled / permission-restricted states |

## 5. Explicitly out of scope

Native mobile apps; marketing CMS beyond core public pages; hardware/RFID event check-in; legacy data migration beyond basic import; multi-language UI beyond the i18n plumbing (English only for MVP); third-party subscription costs; **all accounting integrations**.
