# Dynamic document types, and front/back sides

**Date:** 2026-08-25
**Status:** Approved for planning
**Modules:** M1 (registration), M2 (masters), M3 (member profile), M4 (approval)

## 1. Why

Two problems, one root cause.

**The master is decoration.** `DocumentTypes` (screen A-12) lets an admin
configure a KYC checklist — name, guidance, size ceiling, file types, required,
asked-for. Registration ignores all of it. The three registration documents are
a Prisma *enum* used as a column type, a hardcoded rules table, a hardcoded code
list, hardcoded multipart field names, and hardcoded labels in the admin review
panel. Adding a fourth document is a schema migration and a release across three
apps.

**Two-sided documents cannot be collected.** An Aadhaar card, a driving licence
and a voter ID each carry half their information on the back. The platform has
one file per document type and no way to ask for the second half.

The original decision to hardcode was deliberate — `application.prisma:13` says
the association "does not get to add a fourth one without a code change, which
is the whole point of the redesign." **That decision is reversed here at the
client's explicit direction**, having been raised and reaffirmed. The safety it
bought (nothing can be soft-deleted out from under a live registration) is
preserved by other means: see §4.2 and §8.

## 2. What we are building

1. Registration reads its checklist from the `DocumentTypes` master instead of
   from code.
2. `DocumentTypes` gains a **Sides** setting: *Front only* or *Front and back*.
3. Everything downstream — the applicant's upload step, the completeness check,
   the resubmit page, the reviewer's verify panel, the approval guard — honours
   both.

### Non-goals

- **Per-category checklists** (a Trader asked for different papers than a
  Grower). Considered and deferred; it needs a `DocumentType ↔ Category` join
  and its own admin screen. Nothing here blocks it later — a category filter
  narrows the same list.
- Changing which documents an existing **member profile** asks for. The
  migration is written so profiles behave exactly as they do today (§4.2).
- Accounting integration — parked per `CLAUDE.md`.

## 3. The rule that drives everything

A `DocumentType` row already carries `applies_to` (`APPLICATION` / `MEMBER` /
`BOTH`), `is_required` and `is_active`. Those three fields become load-bearing:

| Surface | Shows | Blocks progress |
|---|---|---|
| Registration form | active rows where `applies_to ∈ {APPLICATION, BOTH}` | rows with `is_required = true` |
| Member profile documents | active rows where `applies_to ∈ {MEMBER, BOTH}` | rows with `is_required = true` are listed as outstanding (a profile has no submit gate) |

`is_active = false` means "not offered for new uploads" — the row disappears from
both checklists, but files already uploaded against it keep resolving. That is
existing semantics, unchanged.

## 4. Data model

### 4.1 New

```prisma
/// How many faces of a physical document must be collected.
enum DocumentSides {
  /// One file is the whole document — a certificate, a PDF statement.
  SINGLE
  /// Two files: an ID card whose reverse carries the address or signature.
  FRONT_AND_BACK
}

/// Which face an uploaded file is.
enum DocumentSide {
  /// The only file for a SINGLE type.
  SINGLE
  FRONT
  BACK
  /// One multi-page PDF carrying both faces of a FRONT_AND_BACK type.
  COMBINED
}
```

- `DocumentType.sides DocumentSides @default(SINGLE)` — every existing row keeps
  behaving as it does today without touching it.
- `ApplicationDocument.side DocumentSide @default(SINGLE)`
- `MemberDocument.side DocumentSide @default(SINGLE)`

### 4.2 Changed — the risky one

`ApplicationDocument.document_type` is today a `RegistrationDocumentType` enum
column. It becomes a foreign key:

```prisma
document_type_id BigInt
document_type    DocumentType @relation(fields: [document_type_id], references: [id], onDelete: Restrict, onUpdate: Cascade)
@@index([application_id, document_type_id])
```

`onDelete: Restrict` is part of what replaces the safety the enum gave, but it is
**not sufficient on its own** — see §4.4.

`MemberDocument` already restricts this way; the two now match.

The `RegistrationDocumentType` enum is dropped once the column is gone.

### 4.4 The bug this reintroduces, and how it is stopped

`ApplicationDocument` **already had** this foreign key. It was removed on
2026-08-24 (migration `20260824130000_m5_application_document_fixed_kyc_type`)
for a stated reason:

> "DocumentTypes rows can be soft-deleted independently — which is exactly what
> broke GST_CERTIFICATE and left registration unable to attach that upload."

Restoring the FK restores that failure mode unless the cause is fixed, and the
cause is not the foreign key. It is that **`deleteDocumentType` has no in-use
guard**. `masters.service.ts:559` soft-deletes unconditionally; its own comment
says "the in-use guard lands with them [MemberDocuments/ApplicationDocuments],
today nothing can reference a type yet." That guard was never written, and
`MemberDocument` has been referencing the table since M3.

`onDelete: Restrict` cannot catch this, because a soft delete is an `UPDATE`
setting `deletedAt`, not a `DELETE`. Postgres never sees a violation.

Three changes close it, and all three are required:

1. **An in-use guard on delete.** `deleteDocumentType` refuses with `409` when
   any `ApplicationDocument` or `MemberDocument` (ignoring soft-deleted files)
   references the type. Screen A-12 already advertises this behaviour —
   `screen-inventory.md` lists A-12 as `in-use-cannot-delete` — so this is
   implementing a documented promise, not adding a rule.
2. **Resolving an existing file's type never filters on `deletedAt`.** A file
   already uploaded must always resolve its type, even if that type was retired.
   Only *checklist* queries filter on `is_active` and `deletedAt`.
3. **`onDelete: Restrict`** as a database-level backstop for a hard delete that
   bypasses the service.

Without item 1 this feature ships the same outage that was rolled back
yesterday. It is Task 2 in the implementation plan, before the migration.

### 4.3 Migration, in one file, in this order

1. **Seed the three canonical rows** if absent — `GST_CERTIFICATE`,
   `PAN_DOCUMENT`, `TRADE_LICENCE`, with the values `REGISTRATION_DOCUMENT_RULES`
   hardcoded: `max_size_mb = 10`, `allowed_mime = {application/pdf, image/jpeg,
   image/png}`, `is_required = true`, `sides = SINGLE`, `is_active = true`.
   `applies_to = APPLICATION` — **not** `BOTH`. Reason: registration behaviour is
   reproduced exactly, and no existing member's profile silently grows three new
   requirements overnight. An admin can flip any of them to `BOTH` from screen
   A-12 afterwards, deliberately.
   Idempotent (`ON CONFLICT (code) DO NOTHING`) — the client already created rows
   by hand and those must survive.
2. Add `document_type_id BIGINT NULL`.
3. Backfill: `UPDATE "ApplicationDocuments" ad SET document_type_id = dt.id FROM
   "DocumentTypes" dt WHERE dt.code = ad.document_type::text`.
4. **Guard:** raise an exception if any row still has `document_type_id IS NULL`.
   A partially-migrated evidence table is worse than a failed deploy.
5. `SET NOT NULL`, add the FK and the new index, drop the old index.
6. Drop `document_type`, then `DROP TYPE "RegistrationDocumentType"`.

`prisma/seed/documentTypes.ts` is added alongside, carrying the same three rows,
so a fresh environment matches a migrated one. `migration-strategy.md` (line 57)
already lists this seed file as expected; it does not currently exist.

## 5. Backend

### 5.1 One source of truth

New in the masters module:

```ts
checklistFor(surface: 'APPLICATION' | 'MEMBER'): Promise<ChecklistItem[]>
```

Returns active rows for that surface ordered by `display_order`, each carrying
`{ id, code, name, description, max_size_mb, allowed_mime, is_required, sides }`.
Every caller below uses it; nothing re-implements the filter.

### 5.2 Deleted

- `REGISTRATION_KYC_CODES` and `REGISTRATION_FILE_FIELDS`
  (`modules/auth/register.constants.ts`)
- `REGISTRATION_DOCUMENT_RULES` and `isRegistrationDocumentType`
  (`modules/document/document.service.ts:362`)
- `listRequiredDocumentTypes()` (`modules/application/application.repository.ts:298`)

### 5.3 Sides logic — one helper, used everywhere

```ts
requiredSides(sides: DocumentSides): DocumentSide[]
// SINGLE          -> [SINGLE]
// FRONT_AND_BACK  -> [FRONT, BACK]

isSatisfied(type, uploaded: DocumentSide[]): boolean
// SINGLE          -> has SINGLE
// FRONT_AND_BACK  -> has COMBINED, or has both FRONT and BACK
```

**A PDF satisfies a two-sided type on its own.** If a `FRONT_AND_BACK` type
receives an `application/pdf`, it is stored as `COMBINED` and the requirement is
met — a scanned card is normally one two-page PDF, and asking the applicant to
split it is busywork. An image upload must specify `FRONT` or `BACK`.

### 5.4 Upload validation

`validateApplicationFileBuffer` takes a document type **row** instead of a code,
and reads `max_size_mb` / `allowed_mime` from it. Magic-byte sniffing is
unchanged — a client-declared MIME is still not evidence (`file-storage.md` §3),
and the SVG rejection stands.

An upload naming an inactive or unknown type is rejected with
`masters.documentTypeNotFound`, as today.

### 5.5 Completeness and the approval guard

`checkCompleteness` currently compares two lists of codes. It becomes a
comparison of `(type, side)` pairs. `missingDocuments` gains a shape the UI can
render precisely — `{ code, name, side }` — so the applicant is told
*"Aadhaar Card (back) is still needed"*, not *"AADHAAR_CARD"*.

`countUnverifiedRequiredDocuments` (the approve guard, spec D-7) counts over the
latest version of **each required side**. A two-sided document is not approvable
until both faces are `VERIFIED`.

### 5.6 The multipart problem

`POST /auth/register` is one multipart request whose multer field names are fixed
at route-definition time (`auth.routes.ts:20`). Dynamic types have no fixed field
names.

**Chosen approach:** wrap multer in a middleware that loads the checklist first,
then invokes `upload.fields(...)` built from it. Field name convention:
`document__<CODE>__<SIDE>`, e.g. `document__AADHAAR_CARD__BACK`.

Rejected: `multer.any()`. It accepts any field name at all, which turns a
whitelist into a free-for-all on a public, unauthenticated endpoint. The file
count cap stays, computed from the checklist rather than from `3`.

### 5.7 New endpoint

`GET /api/v1/public/document-checklist` — anonymous, because the registration
form must render before anyone has an account. Returns the `APPLICATION` surface
from §5.1. No counts, no member data, nothing that is not already printed on the
form. Rate-limited like the other public reads.

The existing `GET /members/me/documents` keeps serving the `MEMBER` surface, now
routed through the same helper.

## 6. Customer app

- **`RegistrationForm.tsx`** — the hardcoded `[gst_certificate, pan_document,
  trade_licence]` list (line 43) is replaced by the fetched checklist. One
  upload control per row, two for a `FRONT_AND_BACK` row, each labelled
  *"Aadhaar Card — front"* / *"— back"*. Client-side validation mirrors the
  server: required rows must be filled, both sides present.
- **`DocumentsStep.tsx`** — already renders from a fetched checklist; it gains
  side-awareness and switches to the public/application checklist rather than
  the member one.
- **`types/resubmit.ts:29`** and **`types/application.ts:311`** — the hardcoded
  triples go. `document_type` on a document becomes `{ code, name }` plus `side`.
- The resubmit page asks only for the sides actually marked
  `requires_reupload` — the existing per-file debt model already supports this
  and needs no change beyond carrying the side through.

## 7. Admin app

Before any screen work, follow the `association-admin-ui` skill.

- **`pages/masters/DocumentTypes.tsx`** — one `FormSelect` labelled **Sides**
  beside *Asked for*: "Front only" / "Front and back". A `Sides` column in the
  table. `FieldLabel help=` explains what the second file is for.
- **`pages/applications/DocumentsPanel.tsx`** — `REGISTRATION_DOCUMENT_LABELS`
  (`applicationsService.ts:169`) is deleted; the panel renders the name the API
  sends. Files group under their document type, one row per side, each with its
  own ✓/✗ so a blurry back can be rejected alone.
- **`pages/members/MemberDocumentsPanel.tsx`** — same side treatment; it already
  reads `document_type.name` from the API.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Migration corrupts live application evidence | Step 4 guard aborts the transaction on any unmatched row; rehearsed against a restored copy before deploy (`backup-recovery.md`) |
| An admin deletes a type that live applications reference — **this exact outage happened on 2026-08-24 and caused the FK to be dropped** | An in-use guard on `deleteDocumentType` (§4.4 item 1), lookups that ignore `deletedAt` when resolving an existing file's type (item 2), and `onDelete: Restrict` as a backstop (item 3). All three, not one. |
| An admin deactivates a type mid-application | Already-uploaded files still resolve; the row leaves the checklist. Same semantics as today's member profile. |
| An admin marks a type required and blocks applicants mid-form | Accepted — it is the point of the feature. Completeness is evaluated at submit, so a draft is never destroyed, only told what is now needed. |
| Public checklist endpoint abused | Rate-limited; returns only what the form displays |
| Registration's file-count cap becomes unbounded | Cap computed from the checklist; a hard ceiling stays in multer config |

## 9. Testing

- **Migration** — rehearse forward on a restored production-shaped copy; assert
  every `ApplicationDocument` resolves to a type and the three canonical rows
  exist exactly once.
- **Backend** — unit tests for `requiredSides` / `isSatisfied` (including the
  PDF-as-COMBINED case), completeness with a two-sided required type, and the
  approve guard refusing a half-verified two-sided document.
- **End to end** — the existing Self-Test Agent walks: admin adds a two-sided
  required type → applicant sees two boxes → submit blocked with one side
  missing → reviewer rejects the back only → applicant replaces the back →
  approve succeeds. Per `CLAUDE.md`, no new testing agent is created.

## 10. Open questions

None blocking. Two worth confirming before the migration lands:

1. **Should the three canonical rows be `APPLICATION` or `BOTH`?** This spec
   chooses `APPLICATION` to preserve current behaviour exactly. If the
   association wants members to keep GST and PAN on their profile too, an admin
   flips them to `BOTH` after deploy — no code change.
2. **Codes are write-once.** An admin creating "Aadhaar Card" gets code
   `AADHAAR_CARD` permanently. That is existing A-12 behaviour and is retained.
