# Assumptions & Open Questions

Rule from `CLAUDE.md`: do not invent business requirements. Anything below marked **OQ** blocks the module it belongs to and must be answered before that module's cycle starts. Assumptions marked **A** are safe defaults being used now; they are reversible and flagged in code with `// ASSUMPTION: A-n`.

## Open Questions (blocking, by module)

| ID | Module | Question | Blocks |
|---|---|---|---|
| OQ-1 | M1 | Exact permission matrix per role (Super Admin / Admin / Approver / Accounts). Proposed matrix in `rbac.md` — needs sign-off. | M1 seed data |
| OQ-2 | M2 | Final membership categories, tiers, fee amounts, membership duration, eligibility rules, benefits. | M2 seed + M4 invoicing |
| ~~OQ-3~~ | ~~M4~~ | **ANSWERED 2026-08-13** — role/permission-driven and configurable; resubmission limit set by super admin (`SystemSettings`). Stage-editor UI deferred to M10. Original question: approval stages: how many, which role approves each, rejection vs return-for-correction rules, resubmission limits, whether workflow is UI-configurable in MVP. | M4 |
| OQ-4 | M5 | Payment gateway provider (Razorpay / PayU / CCAvenue / Stripe …), merchant account availability, settlement/refund policy. | M5 live payments |
| OQ-5 | M8 | WhatsApp Business API provider, approved template list, opt-in handling. | M8 WhatsApp channel |
| OQ-6 | M6 | Renewal rules: reminder schedule (e.g. T-30/T-15/T-7/T-0), grace period length, behaviour after grace (auto-expire? suspend?), auto vs manual renewal. | M6 |
| OQ-7 | M9 | Is the member directory public or login-only? Which fields are visible publicly vs to members? | M9 |
| OQ-8 | **M4 — still open** | Confirmed: approval must raise an invoice. **Not yet answered:** invoice number format, the association's GSTIN, and whether it issues tax invoices. M4 will use the A-12 defaults and must not issue to a real member until these are supplied. Original question: GST treatment on membership/event fees: rate, whether the association issues tax invoices, HSN/SAC code, invoice number format required by the client. | M5 |
| OQ-9 | M2 | Mandatory KYC document list and whether IEC/GST are mandatory for all categories. | M2 document types + M3 upload checklist |
| OQ-10 | staging | Hosting target (VPS vs AWS), file storage (local vs S3), SMTP provider. **No longer blocks M0** — `StorageAdapter` ships a local driver (ADR-017) and mail comes from env. | staging setup |
| OQ-11 | go-live | Off-host backup destination and who holds its credentials | `backup-recovery.md` |
| **OQ-12** | **M0** | **Version control: git hosting, and one monorepo vs three repos like Elvee. The project is currently not under git — see `backup-recovery.md` §7.** | **M0 start** |
| OQ-13 | go-live | Audit log retention period (financial/approval records; commonly 7 years in India) | `observability.md` §7 |
| OQ-14 | scaling | Rate-limit store once more than one API instance runs (in-memory today) | `security.md` §6 |
| OQ-15 | go-live | Retention of KYC documents for rejected/withdrawn applicants | `file-storage.md` §6 |
| OQ-16 | recommendation | 2FA for SUPER_ADMIN / ACCOUNTS roles | `security.md` §3 |
| OQ-17 | recommendation | Virus scanning of uploads before staff open them | `file-storage.md` §6 |
| OQ-18 | go-live | Privacy policy + terms of use content and owner (DPDP) | `security.md` §8 |
| OQ-19 | recommendation | Per-member storage quota / total upload cap | `file-storage.md` §6 |
| OQ-8b | M5 | Does a refund suspend or shorten the membership term? MVP default: term untouched, admin decides manually | `billing-payment.md` §7 |

## Working assumptions (safe defaults)

| ID | Assumption |
|---|---|
| A-1 | Members and admin staff live in **separate tables** (`Users`, `AdminUsers`) with separate JWT audiences. A member can never obtain an admin token. |
| A-2 | One `Member` (company/organisation) has one primary login `User` and optionally additional contact users later. MVP: one login per member. |
| A-3 | Currency is INR only. Money stored `Decimal(14,2)`. |
| A-4 | Membership term is 12 months from approval/renewal date until OQ-2 says otherwise. |
| A-5 | Payment gateway is behind a provider interface; MVP ships a `ManualProvider` (admin records offline payment) + a `MockProvider` for tests, so M5 is not blocked by OQ-4. |
| A-6 | Email is the primary notification channel for MVP; WhatsApp adapter is written to an interface and left unwired until OQ-5. |
| A-13 | **SMTP credentials arrive later** (user, 2026-08-12). Until then M0/M1 use a console transport in `local` and Mailhog/Ethereal in `dev`; the outbox, templates and drain job are fully exercised regardless. Real SMTP is an env swap. |
| A-14 | **Theme is monochrome, ElevenLabs-style** (user, 2026-08-12): near-black on white, neutral grey scale, hairline borders, generous whitespace, no decorative colour. Semantic status colour is retained but muted, and always paired with an icon + label — status must never be colour-only (WCAG). Brand assets (logo/wordmark) still needed from the client per NFR-6. |
| A-15 | **Git deferred** (user, 2026-08-12). Interim controls: strict per-cycle file ownership + tar snapshots at cycle boundaries (R-13). |
| A-7 | Files stored on local disk under `backend/src/public/<domain>/` in dev, behind an authenticated download endpoint; storage is behind a `StorageAdapter` so S3 can be swapped without touching callers. |
| A-8 | ~~Approval copies the application snapshot into `Members`.~~ **Superseded by ADR-016:** the `Members` row is created when the application starts (status `DRAFT`) and holds the live profile; the application stores an immutable snapshot of what was submitted, and approval flips status + assigns `member_code`. |
| A-9 | Soft delete via `deletedAt` on business entities; hard delete only for tokens/OTPs/logs pruning. |
| A-10 | English-only copy for MVP; all strings still go through i18n keys. |
| A-11 | Member self-serve profile edits to KYC-critical fields (company name, IEC, GST, trade licence) require admin approval; non-critical fields (phone, address, website) save directly. |
| A-12 | Invoice numbering `INV/YYYY-YY/00001`, receipt `RCP/YYYY-YY/00001`, member code `LGDGF/YYYY/0001` — pending OQ-8 confirmation. |
