# Registration Redesign — Phase 3: Admin & Member Portal Adjustments

> **Created 2026-08-24** — referenced from revised spec.

**Goal:** Align admin and member UIs with the registration-at-submit flow.

**Depends on:** Phase 2 registration endpoint and set-password flow working.

## Tasks

- [ ] Admin application queue: show registration fields + three KYC documents from `ApplicationDocument`
- [ ] On approve: trigger set-password email (wire into existing activation/approval path)
- [ ] Remove/hide **Document Types** admin screen and routes (spec D-3)
- [ ] Admin: Company Types, Countries, States, Cities master screens (`association-admin-ui`)
- [ ] Admin Fees: flat fee only (no category/tier selectors)
- [ ] Admin member detail: company type, Business Nature list, consent timestamp, location FK labels
- [ ] Customer: remove or gate application stepper — approved members land on dashboard only
- [ ] Customer: set-password page from approval email link

**Spec:** `docs/specs/2026-08-24-registration-redesign.md`
