# M3 — Member Record, Profile, KYC & Member Management

**Status:** AWAITING_APPROVAL (self-test green 2026-08-13) · **Migration owner:** Agent A · **Blocking OQ:** OQ-15 (retention for rejected applicants' documents — before go-live, not before coding) · **Depends on:** M0, M1, M2

> Reordered by ADR-019. Member records now exist from application start (ADR-016), so profile and KYC are buildable before the approval engine.

## Goal
A signed-up user has a company record they can complete and evidence with documents; staff can find, inspect and change the state of any member with a reason on record.

## Agent A — member record + KYC (backend + customer)
- Migration: `Members` (status incl. `DRAFT`, FKs to categories/tiers now that M2 exists), `MemberContacts`, `MemberAddresses`, `MemberDocuments`, `MemberProfileChangeRequests`, `MemberStatusHistory`. All commented.
- `modules/member`: create the `DRAFT` member on first application start (ADR-016), `/members/me` read/update (non-critical fields, A-11), contacts + addresses CRUD, KYC completeness calculation.
- `modules/document`: upload via multer with the full validation chain from `file-storage.md` §3 (authz → type → size → extension → **magic bytes** → SHA-256), versioned re-upload, authorised streaming download with an audit row, orphan cleanup on failed writes.
- Change requests: create + list. Their **approval** lands in M4 with the workflow engine; until then they sit `PENDING` and the UI says so.
- Customer screens C-10 (dashboard shell with real data), C-14…C-17, C-29 partial.

## Agent B — admin side
- `modules/member-admin`: list (raw SQL: search + filters + pagination + single statement), detail aggregate, edit, category/tier change with reason, suspend/reactivate/terminate writing `MemberStatusHistory` + a queued notification, CSV/XLSX export.
- Document review: `GET /admin/members/:id/documents`, `PATCH /admin/documents/:id/verify` (reject requires remarks).
- Admin screens A-07…A-09, A-13.

## Contracts frozen
`Members` field list · critical vs non-critical field split · upload + download DTOs · KYC completeness formula · member list filter/sort allowlist · status-change payload (reason mandatory).

## Self-test
`profile` suite (`testing-strategy.md` §4) plus the storage assertions in `file-storage.md` §8: oversize → 422 with the real limit · declared-PDF-actually-HTML → 422 · direct URL fetch of a KYC path → 404 · another member's document → 404 · admin download → 200 + audit row · re-upload → version 2, both files retained · traversal filename lands inside `STORAGE_PATH` under a UUID · member list is one SQL statement and clamps `limit > 100`.

## Definition of done
- No KYC file reachable without authorization, proven by fetching the raw path.
- Every status change writes history + notification + audit.
- `EXPLAIN ANALYZE` on the member list uses the composite index.
- Duplicate GST/IEC blocked by a partial unique index with a human-readable message.

## Approval checklist
Critical-field list confirmed · what suspension actually blocks · export columns · document retention for rejected applicants (OQ-15).

---

## Cycle record — 2026-08-13

**Sentinel:** `reports/smoke_2026-08-13-09-04-03_pass.md` — **PASS**, ten suites: health · api · crypto · schema · auth · rbac · masters · **profile (36 checks)** · customer · admin.

### Delivered
Six tables (`Members`, `MemberContacts`, `MemberAddresses`, `MemberDocuments`, `MemberProfileChangeRequests`, `MemberStatusHistory`) — schema now **24 tables / 259 columns, every one commented**. Backend `modules/member` + `modules/document`. Customer: profile with the self-edit/approval split, KYC checklist and upload, contacts, addresses, dashboard, directory visibility. Admin: member list (server sort, filters, pending-document badge), detail with Profile/Documents/History, status dialogs, document verification. Sentinel `profile` suite.

### Rules the database enforces, proven by probe
Tier without a category → rejected · GST ≠ 15 chars → rejected · GST/IEC unique across **live** members only · one primary contact and one primary address per member · one open change request per member · a rejection must carry remarks · document versions increment, never overwrite.

### Defects found and fixed in-cycle
| # | Finding | Verdict |
|---|---|---|
| 1 | `Members.primary_user_id`, `category_id` and the admin FKs were declared as plain integer columns — **no foreign keys at all** | Caught before the migration was applied. Relations declared properly so Prisma owns the constraints |
| 2 | Upload size error rendered *"larger than the  MB limit"* | `details` carries machine-readable data; `replacements` fills the message. The one number the member needs was missing |
| 3 | **Admin document download was impossible from a browser** — the route keyed off a client-supplied `x-audience` header that CORS refused (found by Agent B, which stopped rather than editing backend code) | Fixed *differently* from the suggestion: a request must not nominate which authenticator inspects it. The route now reads the token's own `aud` claim via `jwt.decode` (no verification) to pick the verifier; the chosen middleware still verifies signature, expiry and audience, so a forged claim buys nothing. `Content-Disposition` added to `exposedHeaders` |
| 4 | `file_path` (the storage key) was serialised to clients (found by Agent A) | Redacted from every member/document response. Unreachable over HTTP either way — but publishing internal layout is how a bucket name later ends up in a devtools tab |
| 5 | `purgeSentinelUsers` deleted `Users` before `Members`, which `ON DELETE RESTRICT` forbids | Would have broken cleanup for every future suite touching `/members/me` |
| 6 | Agent A's gating run hit a **stale backend process** (started 09:32, source changed 14:21) | It said so rather than claiming a pass. Re-run after restart: green |

### Open, carried forward
- **Category picker has no member-facing ids.** `PATCH /members/me` accepts `category_id` while DRAFT, but the public catalogue publishes codes only, so C-15 renders class read-only. **Decision: correct as-is** — category is chosen during the application (C-11, M4), not on the profile screen. M4 wires the picker.
- Pre-existing dev-only AntD `cssVar` warning from M0 (`AntdApp component={false}`). Left alone deliberately: the fix adds a wrapping element app-wide, which is not an end-of-cycle change for a dev-only warning.
- OQ-15 (retention for rejected applicants' documents) still unanswered — soft delete keeps files meanwhile.
