# Scope

## In scope (MVP)

| Cycle | Module | Owner |
|---|---|---|
| M0 | Foundation & shared core (encryption, i18n, identity, audit, storage, outbox, observability) | B (+A shells) |
| M1 | Authentication & Account, RBAC | B core, A member side |
| M2 | Masters: categories, tiers, fees, document types | B |
| M3 | Member record, profile, KYC, documents, member management | A (+B admin) |
| M4 | Membership application, approval workflow, activation, invoice issuance | B engine, A applicant |
| M5 | Payments, receipts, refunds, reconciliation, dunning | B (+A member billing) |
| M6 | Membership renewal | B (+A member screens) |
| M7 | Event management | B admin, A member |
| M8 | Communication & notifications | B (+A member inbox) |
| M9 | Member directory & public website | A |
| M10 | Dashboard, reports, hierarchy/designations, audit, settings | B |

RBAC (FR-14) is built in M0/M1 as the permission engine and extended per module.
Audit (FR-20) is a M0 primitive; each module registers its own audit events.

## Out of scope — hard stop

- **Accounting integration** (Tally, Zoho Books, QuickBooks, Refrens, Vyapar), two-way sync, reconciliation against external books. PARKED per `CLAUDE.md` — **but it is inside the signed proposal** (Admin Portal item 5). It is therefore *deferred*, not descoped: no schema, no adapters, no config now, and a written change note to the client is required so the deferral is agreed rather than discovered. Tracked as PV-4.
- Native iOS/Android apps.
- Marketing CMS / page builder beyond fixed public pages.
- RFID / badge / hardware event check-in.
- Legacy data migration **beyond** basic import. Note: the proposal excludes only what is *beyond* basic import, so a member CSV import utility is arguably in scope — confirm (PV-5). Currently planned as an optional M10 item.
- Non-English UI copy. (i18n plumbing IS in scope; only `en.json` is populated.)

## Scope-change rule

Any change to this file requires: a line in `architecture-decisions.md`, an update to the affected module plan file in `docs/modules/`, and user approval. Coding agents may not expand scope on their own.
