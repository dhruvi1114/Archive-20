# Registration Redesign — Specification

**Date:** 2026-08-24 (revised 2026-08-24 after user decisions in conversation)
**Status:** Approved — revised flow locked on 2026-08-24.
**Supersedes:** the small five-field signup and post-login application stepper described in `docs/customer-user-journeys.md` CJ-1 and CJ-2.

---

## 1. Why

The association wants registration to work the way GJEPC's does: **one long public form collects the company's whole identity and KYC documents up front**. The applicant does not log in to finish an application. Staff review the complete package in the admin queue; only after approval does the member set a password and access the portal.

Today the platform asks for five fields at signup, then five application steps behind the login wall. That leaves half-registered members staff cannot assess and duplicates work the reference form collects once.

---

## 2. Decisions taken

| # | Decision | Consequence |
|---|---|---|
| D-1 | One big public registration form, GJEPC layout | `SignupForm.tsx` rebuilt |
| D-2 | **KYC documents are collected at registration**, not after login | Three fixed uploads on the public form; application stepper removed for new applicants |
| D-3 | **Fixed KYC list — not from Document Types master** | Exactly three required uploads: GST certificate, PAN document, Trade licence. Admin Document Types CRUD is removed/hidden |
| D-4 | **No password at registration** | `Users.password_hash` NULL until first set; GJEPC-style deferred credentials (D-12) |
| D-5 | **Login only after admin approval + password set** | New `Users.status` value `PENDING_APPROVAL`; no portal access until approve → set password (Option B) |
| D-6 | **Tiers are not used.** Every member pays the same | `MembershipTiers` stays in the schema, left empty |
| D-7 | **Price does not depend on category** | `FeeStructures.category_id` becomes nullable |
| D-8 | Business Nature uses **`MembershipCategories` master** — label only differs | No new business-nature table |
| D-9 | Business Nature is **multi-select** | Join table `MemberCategories`; `Members.category_id` dropped |
| D-10 | Company Type is a **master** | New table `CompanyTypes` |
| D-11 | Country / State / City are **masters** with cascading selects | New tables `Countries`, `States`, `Cities` |
| D-12 | **First password via emailed link after approval** (Option B) | Reuse/extend `PasswordResetToken` flow; after approve → `PENDING_VERIFICATION` → set password → `ACTIVE` |
| D-13 | "Company Category" Yes/No radio **kept** as on reference form | `Members.company_category` nullable boolean — OQ-R1 |
| D-14 | Consent text editable by staff | `SystemSetting` key `registration.consent_text` |
| D-15 | Captcha required on the public form | Stateless signed captcha service |

---

## 3. Open questions

- **OQ-R1 — What does "Company Category: Yes / No" mean?** Stored verbatim; nothing reads it until the association defines it.
- **OQ-R3 — May a member change Business Nature later without approval?** Assumed yes unless the association says otherwise.
- **OQ-R4 — City coverage.** Gujarat and Maharashtra full; other states principal cities only.
- **OQ-R5 — No person-name field on the form.** `Users.full_name` ← company name until the association asks for a signatory.
- **OQ-R6 — Return for correction without login.** ~~Not in v1.~~ **Resolved 2026-08-25** — see `docs/specs/2026-08-25-reject-resubmit-flow.md`. Reject now sends the application back through a login-free token link, capped by `application.max_resubmissions`; Return is removed entirely.

---

## 3a. Structural rules

1. **Registration writes the member eagerly.** `Users` + `Members` + `MemberCategories` + `MemberAddresses` + `ApplicationDocument` (×3) + `MembershipApplication` (`SUBMITTED`) in one transaction. Lazy member provisioning remains for pre-change accounts only.

2. **Enumeration-safe signup survives.** Same success response whether or not the email is already registered; verified accounts write nothing.

3. **Document types are code constants, not admin config.** Three seeded rows (`GST_CERTIFICATE`, `PAN_DOCUMENT`, `TRADE_LICENCE`) exist for FK integrity; staff do not manage them in admin.

---

## 4. The registration form

Three sections, three columns on desktop, stacked on mobile. Labels match the GJEPC reference form unless noted.

### 4.1 Account Information

| Label | Control | Required | Notes |
|---|---|---|---|
| Email address (Username) | text | Yes | `Users.email` |
| Company PAN No | text | Yes | `Members.pan_number` — also typed, separate from PAN **document** upload |
| GSTIN Holder Status | radio Yes/No | Yes | Default No → `Members.gstin_holder` |
| Company GSTIN | text | When holder = Yes | Disabled / `N/A` when No |
| Company Category | radio Yes/No | No | OQ-R1 → `Members.company_category` |

**No password field** (D-4).

### 4.2 Company Information

| Label | Control | Source | Required |
|---|---|---|---|
| Company Name | text | — | Yes |
| Company Type | radio | `CompanyTypes` | Yes |
| Address Line 1 / 2 | text | — | Line 1 yes |
| Pin code | text | — | Yes |
| Country / State / City | selects | location masters | Yes (city optional if none seeded) |
| Landline No | text | — | No |
| Mobile No | text | — | Yes |
| Business Nature | checkboxes | `MembershipCategories` | Yes, ≥1 |

### 4.3 KYC Documents (fixed — D-2, D-3)

| Upload | Code constant | Required |
|---|---|---|
| GST certificate | `GST_CERTIFICATE` | Yes |
| PAN document | `PAN_DOCUMENT` | Yes |
| Trade licence | `TRADE_LICENCE` | Yes |

Stored as `ApplicationDocument` rows on the `MembershipApplication` created at submit (primary category = first selected Business Nature).

### 4.4 Terms of Agreement

| Label | Control | Required |
|---|---|---|
| Consent paragraph | read-only scroll box | — |
| I confirm… | checkbox | Yes |
| Captcha | text + image | Yes |
| Submit / Reset | buttons | — |

### 4.5 Conditional rules

1. GSTIN Holder = No → GSTIN null; field disabled showing `N/A`.
2. Country change → reset state and city.
3. State change → reset city; if no cities, city not required.

---

## 5. End-to-end flow

| Step | Actor | Result | Status after |
|---|---|---|---|
| 1 | Visitor | Submits registration (form + 3 docs) | `Users.PENDING_APPROVAL`, `password_hash` NULL, `Members.DRAFT`, `MembershipApplication.SUBMITTED` |
| 2 | Visitor | Sees confirmation — **cannot log in** | unchanged |
| 3 | Admin | Opens queue, reviews data + 3 documents | `UNDER_REVIEW` |
| 4 | Admin | Approve or Reject | Approve → email set-password link; Reject → email reason, terminal |
| 5 | Visitor | Sets password via emailed link (Option B) | `Users.PENDING_VERIFICATION` → `ACTIVE`, `email_verified_at` set |
| 6 | Member | Logs in (email + password) | portal access |
| 7 | System | On approve: member code + invoice (existing) | `Members.PENDING` |
| 8 | Member | Pays invoice (existing) | `Members.ACTIVE` |

Steps 3–4 reuse the existing approval engine. Steps 7–8 are unchanged billing.

**Removed for new applicants:** signup OTP, post-login application stepper (Company / Contact / Documents / Category / Review).

---

## 6. Data model

### 6.1 New tables

`CompanyTypes`, `Countries`, `States`, `Cities`, `MemberCategories` — as in the 2026-08-24 schema plan (see Phase 1 implementation plan).

### 6.2 Altered tables

**`Users`**

- `password_hash` → **nullable** (D-4)
- `UserStatus` enum → add **`PENDING_APPROVAL`** (D-5)
- Default status for new registrations → `PENDING_APPROVAL`

**`Members`** — add `company_type_id`, `gstin_holder`, `company_category`, `landline`, `consent_accepted_at`, `consent_ip`; drop `category_id`, `tier_id`, `business_type`.

**`MemberAddresses`** — add `country_id`, `state_id`, `city_id`; keep text snapshot columns.

**`FeeStructures`** — `category_id` nullable; overlap constraint uses `COALESCE(category_id, -1)`.

**`DocumentTypes`** — table **kept**; three rows **seeded**; admin CRUD **removed** (D-3).

**`MembershipApplications`** — unchanged columns; created at registration already `SUBMITTED` with snapshot fields.

---

## 7. Backend surface

### 7.1 Public (no auth)

```
GET   /api/v1/public/registration-options     company types + countries
GET   /api/v1/public/states?country_id=
GET   /api/v1/public/cities?state_id=
GET   /api/v1/public/registration-consent
GET   /api/v1/public/membership               Business Nature checkboxes
GET   /api/v1/auth/captcha
POST  /api/v1/auth/register                   multipart: JSON fields + 3 files
POST  /api/v1/auth/set-initial-password       token from approval email
```

`POST /api/v1/auth/signup` is **replaced** by `POST /api/v1/auth/register` (or signup rewritten to the new contract — one public registration endpoint only).

### 7.2 Admin

- Location + company-type masters CRUD (unchanged from prior plan).
- **Document Types admin routes removed/hidden** (D-3).
- Application queue shows registration submissions with embedded KYC files.

### 7.3 Auth rules

| Status | May log in? |
|---|---|
| `PENDING_APPROVAL` | No |
| `PENDING_VERIFICATION` (after approve, before password set) | No — must complete set-password link |
| `ACTIVE` | Yes |
| `INACTIVE` / `BLOCKED` | No |

---

## 8. Frontend surface

**Customer**

- Public registration page: §4 fields + three file inputs + consent + captcha.
- Confirmation page after submit (no login prompt).
- Set-password page (from approval email).
- Login page unchanged (works only after step 5).
- **Remove** application stepper entry for new registrations; dashboard for approved members only.

**Admin**

- Company Types, Countries, States, Cities master screens.
- **Remove** Document Types screen.
- Application/registration queue shows three KYC files.
- Fees: flat (no category/tier selectors).

---

## 9. Out of scope

Tiers, accounting integration, Hindi translation, admin-configurable document checklists, return-for-correction without login (OQ-R6 v1), changes to invoice/payment logic beyond using existing approve path.

---

## 10. Verification

- `npm run typecheck` and `npm run lint` in each package
- `npx prisma migrate status` clean
- Register → admin queue shows row + 3 files → approve → set password → login → pay (if fee configured)
- Enumeration-safe duplicate email submit
- Self-Test Agent for full journey
