# M2 — Masters: Categories, Tiers, Fees & Document Types

**Status:** AWAITING_APPROVAL (self-test green 2026-08-13) · **Migration owner:** Agent B · **Blocking OQ:** OQ-2 (categories, tiers, fee amounts, duration, eligibility), OQ-9 (mandatory document list) · **Depends on:** M0, M1

> Reordered by ADR-019. Masters must exist before the application form (category + live fee) and before approval (fee resolution).

## Goal
The association's product catalogue exists as data: what you can join, what it costs, for how long, and which documents you must supply.

## Agent B — backend + admin
- Migration: `MembershipCategories`, `MembershipTiers`, `FeeStructures` (with the `btree_gist` daterange exclusion constraint), `DocumentTypes`. All tables/columns commented (ADR-013).
- `modules/membership-category`: category + tier CRUD, display order, activate/deactivate, in-use delete guards.
- `modules/fee`: fee structure CRUD, overlapping effective-date rejection, and the **fee resolution service** (`billing-payment.md` §2) — used by M4 approval, M5 invoicing and M6 renewal.
- `modules/document-type`: CRUD with `allowed_mime`, `max_size_mb`, `applies_to`, `is_required`.
- Seeds: `seed/categories.ts`, `seed/fees.ts`, `seed/documentTypes.ts` — populated from the OQ-2/OQ-9 answers, idempotent upsert by code.
- Admin screens A-10 (categories & tiers), A-11 (fee structures), A-12 (document types).

## Agent A — customer surface
- `/membership` public page: categories, tiers, fees, benefits rendered from live data (C-03).
- `GET /document-types` checklist consumed by the upload UI built in M3.

## Contracts frozen
Category/tier/fee/document-type DTOs · fee resolution rule (tier-specific beats category-wide, newest effective wins) · `allowed_mime` + size limits per document type.

## Self-test
`schema` + new `masters` suite: overlapping active fee for the same (category, tier, type) → 409 with the conflicting row · deleting an in-use category → 409 with counts · fee resolution unit tests across tier-specific vs category-wide and date boundaries · no fee match → explicit error, never a silent ₹0 · `db:check-comments` zero.

## Definition of done
- Fee resolution is a single service used everywhere money is calculated — no second implementation anywhere.
- Deactivate is possible; delete is blocked whenever history references the row.
- Public membership page renders from the DB, not hardcoded copy.

## Approval checklist
Final categories, tiers, amounts, tax treatment, duration and eligibility (OQ-2) · required document list per category (OQ-9).

---

## Cycle record — 2026-08-13

**Sentinel:** `reports/smoke_2026-08-13-02-56-42_pass.md` — **PASS**, nine suites: health · api · crypto · schema · auth · rbac · **masters** · customer · admin.

### Delivered
Schema `MembershipCategories`, `MembershipTiers`, `FeeStructures`, `DocumentTypes` — **18 tables / 181 columns, every one commented** (ADR-013). Backend `modules/masters` (types → repository → service → controller → routes) with the fee resolver M4/M5/M6 will bill against. Admin screens A-10 (categories + tiers), A-11 (fee structures), A-12 (document types). Public membership page C-03, server-rendered. Sentinel `masters` suite, 13 assertions.

### Deviation from the plan
`implementation-plan.md` names three modules (`membership-category`, `fee`, `document-type`). Shipped as one `masters` module with per-entity files instead: three tightly-coupled configuration tables, one router, one permission story. Layering is unchanged (RULES.md), and the fee resolver still lives in exactly one place.

### Rules the database enforces, not just the service
- Exclusion constraint (`btree_gist`) rejects two active prices covering the same day for the same category + tier + fee type. **The service translates the violation; it does not adjudicate it** — so two admins saving at once cannot both win.
- Partial unique on `(category_id, code)` for tiers, so two categories may each have a GOLD and a soft-deleted code can be reused.
- CHECKs: amount ≥ 0, tax 0–100, duration > 0, effective range ordered, upload size 1–50 MB, at least one MIME type.

### Defects found and fixed during the cycle
| # | Finding | Verdict |
|---|---|---|
| 1 | `fee_type::text` in the exclusion constraint → `functions in index expression must be marked IMMUTABLE` | Enum→text casts are STABLE. btree_gist compares the enum directly |
| 2 | **`emit-db-comments` silently skipped every scalar array**, so `DocumentTypes.allowed_mime` shipped uncommented | Real generator bug — it excluded all lists to filter relation arrays. `db:check-comments` caught it, which is the entire reason that gate exists. Fixed and the migration re-applied from empty |
| 3 | **`rbacRouter` applied `authorize('rbac.manage') + requireSuperAdmin` router-wide** on `/admin`, so an ACCOUNTS admin calling `/admin/fee-structures` — a route it does not own — got 403 | Real bug, and it would have hit every future `/admin` module. Guards now bind to `/roles` and `/admin-users`, making mount order irrelevant |
| 4 | Overlapping price returned **500** | Prisma has no mapping for exclusion violations: `PrismaClientUnknownRequestError`, `code` and `meta` both undefined, SQLSTATE `23P01` only in the message. Matcher now checks the message for both the code and the constraint name |
| 5 | Admin screens 404'd against the API | `mastersService` hardcoded paths without the `API_BASE` prefix. Endpoints moved into `constant/endpoints.ts` alongside the rest |
| 6 | Sentinel's own traffic tripped the login throttle, reporting three suites red | Harness defect. One cached admin token per account per run (`testing-strategy.md` §4) |

### Still empty, by design
No categories, tiers, fees or document types are seeded. **OQ-2 and OQ-9 remain unanswered**, and a plausible-looking default would quietly become the federation's price list. Both the admin tables and the public page carry empty states that say so.
