# Dynamic Document Types & Front/Back Sides — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the registration KYC checklist read from the `DocumentTypes` master instead of hardcoded constants, and add a per-type "Front only / Front and back" setting that flows through upload, completeness, review and approval.

**Architecture:** `ApplicationDocument.document_type` stops being a Prisma enum column and becomes a foreign key to `DocumentTypes`, matching how `MemberDocument` already works. One backend helper (`checklistFor`) becomes the single source of "which documents does this surface ask for", and one pure module (`document.sides.ts`) answers "how many files does this type need, and are they all here". Every hardcoded list — in the backend, the customer app and the admin app — is deleted and replaced by a read of that master.

**Tech Stack:** Node.js + Express + TypeScript, Prisma 6 + PostgreSQL, Vitest (added in Task 0), Next.js customer app, React + Vite + Ant Design admin app.

**Spec:** `docs/superpowers/specs/2026-08-25-dynamic-document-types-and-sides-design.md` — read it before Task 1. Every task below argues from it.

## Global Constraints

- **This directory is NOT a git repository.** `git rev-parse` fails at the project root. Every task therefore ends with a **Checkpoint** step (typecheck + lint + the task's own verification) instead of a commit. If you run `git init` first, replace each Checkpoint with the commit shown in its note.
- **Prisma migrations only.** Never `prisma db push`, never edit an already-applied migration (`CLAUDE.md`). New migrations are created with `npm run prisma:migrate:create`, the SQL is written by hand, then applied.
- **Every new column and table carries a `///` doc comment.** `npm run db:check-comments` must return zero rows — it is a Sentinel gate (`testing-strategy.md` §4, ADR-013).
- **Business logic lives in the backend** (`CLAUDE.md`). The customer and admin apps render what the API sends; neither re-implements the checklist rule.
- **Before touching any admin screen, invoke the `association-admin-ui` skill.** Pages must not import `Table`, `Select`, `Button`, `Modal`, `InputNumber`, `Checkbox.Group` or `Pagination` from `antd`; no page sets a colour, radius, height or font-size.
- **MIME allowlist is closed.** `image/svg+xml` is never addable — SVG executes script and these files are opened by staff (`file-storage.md` §3). Magic-byte sniffing stays on every upload path.
- **Sides values are exactly** `SINGLE` / `FRONT_AND_BACK` (on the type) and `SINGLE` / `FRONT` / `BACK` / `COMBINED` (on a file). No other spellings.
- **Admin copy is Title Case for labels, sentence case for sentences.** The Sides field label is `Sides`; its options are `Front only` and `Front and back`.
- **Verification commands** (run from the named directory):
  - backend: `npm run typecheck`, `npm run lint`, `npm test`
  - admin: `npx tsc -p tsconfig.app.json --noEmit`
  - customer: `npx tsc --noEmit`
- **Backend baseline: CLEAN.** The 4 `allow_return` errors seen before Task 0 were a stale Prisma client; Task 0's `npm install` reran `prisma generate` and they are gone. `npm run typecheck` must stay at zero errors from here on.
- **Admin baseline: 4 pre-existing unused-variable errors** in `pages/masters/Categories.tsx` and `Fees.tsx`. Your task fails if the count goes up or new files appear.

---

### Task 0: Test harness

The repo has no test runner. `docs/testing-strategy.md` §3 prescribes **Vitest** for unit tests and Vitest + Supertest for integration. Every later task is written TDD-first and cannot start without it.

**Files:**
- Modify: `backend/package.json`
- Create: `backend/vitest.config.mts` (**`.mts`, not `.ts`** — the package is CJS and `vite-tsconfig-paths` v5 is ESM-only; a `.ts` config is loaded via `require` and fails)
- Create: `backend/src/modules/document/document.sides.test.ts` (smoke test, replaced in Task 1)

**Interfaces:**
- Consumes: nothing
- Produces: `npm test` in `backend/` runs Vitest over `src/**/*.test.ts` with the `@modules`, `@constant`, `@middleware` path aliases resolved.

- [ ] **Step 1: Install Vitest**

```bash
cd backend
npm install --save-dev vitest@^2 vite-tsconfig-paths@^5
```

- [ ] **Step 2: Create the config**

Create `backend/vitest.config.mts`:

```ts
import tsconfigPaths from 'vite-tsconfig-paths';
import { defineConfig } from 'vitest/config';

/**
 * Unit and integration tests (testing-strategy.md §3).
 *
 * `vite-tsconfig-paths` reuses the `@modules` / `@constant` aliases already in
 * tsconfig rather than restating them here, so a new alias never has to be added
 * in two places.
 */
export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'node',
    restoreMocks: true,
  },
});
```

- [ ] **Step 3: Add the script**

In `backend/package.json`, add to `"scripts"` immediately after `"lint:fix"`:

```json
    "test": "vitest run",
    "test:watch": "vitest",
```

- [ ] **Step 4: Write a smoke test that fails**

Create `backend/src/modules/document/document.sides.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

describe('vitest harness', () => {
  it('runs', () => {
    expect(1 + 1).toBe(2);
  });
});
```

- [ ] **Step 5: Run it**

Run: `cd backend && npm test`
Expected: PASS, 1 test. If the run reports "No test files found", the `include` glob or the install failed — fix before continuing.

- [ ] **Step 6: Checkpoint**

Run: `cd backend && npm run typecheck && npm run lint`
Expected: the 4 baseline errors, no new ones.
*(If you ran `git init`: `git add backend/package.json backend/package-lock.json backend/vitest.config.ts backend/src/modules/document/document.sides.test.ts && git commit -m "test: add vitest harness"`)*

---

### Task 1: Sides helpers

Two pure functions that every later task depends on. No database, no Prisma — this is the one piece that is trivially testable and must be right.

**Files:**
- Create: `backend/src/modules/document/document.sides.ts`
- Modify: `backend/src/modules/document/document.sides.test.ts` (replace the Task 0 smoke test)

**Interfaces:**
- Consumes: nothing
- Produces:
  - `requiredSides(sides: 'SINGLE' | 'FRONT_AND_BACK'): DocumentSideValue[]`
  - `isSatisfied(sides: 'SINGLE' | 'FRONT_AND_BACK', uploaded: DocumentSideValue[]): boolean`
  - `missingSides(sides, uploaded): DocumentSideValue[]`
  - `sideForUpload(sides, requestedSide, mimeType): DocumentSideValue` — decides what to store a file as
  - `SIDE_LABELS: Record<DocumentSideValue, string>`
  - `describeSide(name: string, side: DocumentSideValue): string` — "Aadhaar Card (back)"; called by Tasks 6 and 8
  - type `DocumentSideValue = 'SINGLE' | 'FRONT' | 'BACK' | 'COMBINED'`

These are declared as string-literal unions rather than imported from `@prisma/client`, so Task 1 can be written and tested **before** the migration in Task 2 exists. Task 2 does not change them; the Prisma enums are declared with identical members and assign structurally.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `backend/src/modules/document/document.sides.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import {
  isSatisfied,
  missingSides,
  requiredSides,
  sideForUpload,
  SIDE_LABELS,
} from '@modules/document/document.sides';

describe('requiredSides', () => {
  it('asks for one unnamed file for a single-sided type', () => {
    expect(requiredSides('SINGLE')).toEqual(['SINGLE']);
  });

  it('asks for a front and a back for a two-sided type', () => {
    expect(requiredSides('FRONT_AND_BACK')).toEqual(['FRONT', 'BACK']);
  });
});

describe('isSatisfied', () => {
  it('is unsatisfied when a single-sided type has nothing', () => {
    expect(isSatisfied('SINGLE', [])).toBe(false);
  });

  it('is satisfied when a single-sided type has its file', () => {
    expect(isSatisfied('SINGLE', ['SINGLE'])).toBe(true);
  });

  it('is unsatisfied when only the front of a two-sided type is present', () => {
    expect(isSatisfied('FRONT_AND_BACK', ['FRONT'])).toBe(false);
  });

  it('is unsatisfied when only the back of a two-sided type is present', () => {
    expect(isSatisfied('FRONT_AND_BACK', ['BACK'])).toBe(false);
  });

  it('is satisfied when both faces of a two-sided type are present', () => {
    expect(isSatisfied('FRONT_AND_BACK', ['BACK', 'FRONT'])).toBe(true);
  });

  it('accepts one combined PDF as both faces', () => {
    expect(isSatisfied('FRONT_AND_BACK', ['COMBINED'])).toBe(true);
  });

  it('ignores a combined file on a single-sided type', () => {
    expect(isSatisfied('SINGLE', ['COMBINED'])).toBe(false);
  });
});

describe('missingSides', () => {
  it('names the face that is missing', () => {
    expect(missingSides('FRONT_AND_BACK', ['FRONT'])).toEqual(['BACK']);
  });

  it('names nothing when a combined PDF covers both', () => {
    expect(missingSides('FRONT_AND_BACK', ['COMBINED'])).toEqual([]);
  });

  it('names the single file when nothing is uploaded', () => {
    expect(missingSides('SINGLE', [])).toEqual(['SINGLE']);
  });
});

describe('sideForUpload', () => {
  it('stores a single-sided upload as SINGLE whatever the caller asked for', () => {
    expect(sideForUpload('SINGLE', 'FRONT', 'image/jpeg')).toBe('SINGLE');
  });

  it('stores a PDF for a two-sided type as COMBINED', () => {
    expect(sideForUpload('FRONT_AND_BACK', 'FRONT', 'application/pdf')).toBe('COMBINED');
  });

  it('stores an image for a two-sided type as the face requested', () => {
    expect(sideForUpload('FRONT_AND_BACK', 'BACK', 'image/png')).toBe('BACK');
  });

  it('defaults a two-sided image upload with no face named to FRONT', () => {
    expect(sideForUpload('FRONT_AND_BACK', undefined, 'image/png')).toBe('FRONT');
  });
});

describe('SIDE_LABELS', () => {
  it('gives a two-sided face a name a member would recognise', () => {
    expect(SIDE_LABELS.BACK).toBe('back');
  });

  it('gives a single file no qualifier', () => {
    expect(SIDE_LABELS.SINGLE).toBe('');
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npm test`
Expected: FAIL — "Cannot find module '@modules/document/document.sides'".

- [ ] **Step 3: Write the implementation**

Create `backend/src/modules/document/document.sides.ts`:

```ts
/**
 * How many faces of a document must be collected, and whether they are all here.
 *
 * Pure — no Prisma, no I/O — because four callers depend on this answer
 * (upload validation, the applicant's checklist, the completeness gate and the
 * approve guard) and they must not each reimplement it.
 *
 * The literal unions mirror the Prisma enums `DocumentSides` and `DocumentSide`
 * exactly. They are restated rather than imported so this module can be tested
 * without a generated client.
 */

export type DocumentSidesValue = 'SINGLE' | 'FRONT_AND_BACK';
export type DocumentSideValue = 'SINGLE' | 'FRONT' | 'BACK' | 'COMBINED';

/** What the member is asked to hand over. Order is the order they are shown in. */
export const requiredSides = (sides: DocumentSidesValue): DocumentSideValue[] =>
  sides === 'FRONT_AND_BACK' ? ['FRONT', 'BACK'] : ['SINGLE'];

/**
 * Which faces are still owed.
 *
 * A `COMBINED` file settles a two-sided requirement on its own: a scanned ID is
 * normally one two-page PDF, and splitting it is busywork we would be imposing
 * on the applicant for the reviewer's convenience (spec §5.3).
 */
export const missingSides = (
  sides: DocumentSidesValue,
  uploaded: DocumentSideValue[],
): DocumentSideValue[] => {
  if (sides === 'FRONT_AND_BACK' && uploaded.includes('COMBINED')) return [];

  const held = new Set(uploaded);

  return requiredSides(sides).filter((side) => !held.has(side));
};

/** Is this document type's requirement fully met by the files listed? */
export const isSatisfied = (sides: DocumentSidesValue, uploaded: DocumentSideValue[]): boolean =>
  missingSides(sides, uploaded).length === 0;

/**
 * What to store an incoming file as.
 *
 * The caller's requested side is advisory: a single-sided type stores `SINGLE`
 * however the request was labelled, and a PDF against a two-sided type is
 * `COMBINED` regardless — otherwise an applicant could upload the same PDF twice
 * and be recorded as having supplied two different faces.
 */
export const sideForUpload = (
  sides: DocumentSidesValue,
  requested: DocumentSideValue | undefined,
  mimeType: string,
): DocumentSideValue => {
  if (sides === 'SINGLE') return 'SINGLE';
  if (mimeType === 'application/pdf') return 'COMBINED';

  return requested === 'BACK' ? 'BACK' : 'FRONT';
};

/**
 * How a face is named in a sentence — "Aadhaar Card (back) is still needed".
 * Empty for a single file, so the qualifier can be appended unconditionally.
 */
export const SIDE_LABELS: Record<DocumentSideValue, string> = {
  SINGLE: '',
  FRONT: 'front',
  BACK: 'back',
  COMBINED: 'both sides',
};

/** "Aadhaar Card (back)", or just "PAN Card" for a single-sided type. */
export const describeSide = (name: string, side: DocumentSideValue): string =>
  SIDE_LABELS[side] ? `${name} (${SIDE_LABELS[side]})` : name;
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd backend && npm test`
Expected: PASS, 17 tests.

- [ ] **Step 5: Checkpoint**

Run: `cd backend && npm run typecheck && npm run lint`
Expected: baseline errors only.
*(git: `git add backend/src/modules/document/document.sides.ts backend/src/modules/document/document.sides.test.ts && git commit -m "feat(document): add front/back sides helpers"`)*

---

### Task 2: In-use guard on document type delete

**Do this before the migration.** This feature restores a foreign key that was
deliberately dropped yesterday (`20260824130000_m5_application_document_fixed_kyc_type`)
because "DocumentTypes rows can be soft-deleted independently — which is exactly
what broke GST_CERTIFICATE and left registration unable to attach that upload."

The foreign key was not the cause. `deleteDocumentType` soft-deletes with no
in-use check — its own comment at `masters.service.ts:563` says the guard "lands
with them [MemberDocuments/ApplicationDocuments]" and it was never written.
`onDelete: Restrict` cannot catch a soft delete, because that is an `UPDATE`,
not a `DELETE`. Ship the migration without this task and the same outage returns.

`screen-inventory.md` line 55 already lists A-12 as `in-use-cannot-delete`, so
this implements a documented promise.

**Files:**
- Modify: `backend/src/modules/masters/masters.repository.ts` (add `countDocumentTypeUsage`)
- Modify: `backend/src/modules/masters/masters.service.ts:559-577` (`deleteDocumentType`)
- Modify: `backend/src/locales/en.json` (new message key)
- Create: `backend/src/modules/masters/masters.documentTypes.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `countDocumentTypeUsage(db: Db, id: bigint): Promise<number>` — live (non-soft-deleted) files across both document tables; `deleteDocumentType` throws `AppError` with `messageKey: 'masters.documentTypeInUse'` and `ERROR_TYPES.CONFLICT` when that count is above zero.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/masters/masters.documentTypes.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

const repo = vi.hoisted(() => ({
  findDocumentTypeById: vi.fn(),
  countDocumentTypeUsage: vi.fn(),
  updateDocumentType: vi.fn(),
}));

vi.mock('@modules/masters/masters.repository', () => repo);
vi.mock('@db/prisma', () => ({
  prisma: { $transaction: (fn: (tx: unknown) => unknown) => fn({}) },
}));
vi.mock('@helpers/audit', () => ({ writeAudit: vi.fn() }));

const { deleteDocumentType } = await import('@modules/masters/masters.service');

const ACTOR = { id: 1n, ip: null, userAgent: null, requestId: null };

describe('deleteDocumentType', () => {
  beforeEach(() => {
    repo.findDocumentTypeById.mockResolvedValue({ id: 7n, code: 'PAN_DOCUMENT', name: 'PAN Card' });
    repo.countDocumentTypeUsage.mockResolvedValue(0);
  });

  it('refuses to retire a type that uploaded files still point at', async () => {
    repo.countDocumentTypeUsage.mockResolvedValue(3);

    await expect(deleteDocumentType(7n, ACTOR)).rejects.toMatchObject({
      messageKey: 'masters.documentTypeInUse',
    });
    expect(repo.updateDocumentType).not.toHaveBeenCalled();
  });

  it('soft-deletes a type nothing references', async () => {
    await deleteDocumentType(7n, ACTOR);

    expect(repo.updateDocumentType).toHaveBeenCalledWith(
      expect.anything(),
      7n,
      expect.objectContaining({ is_active: false, deletedAt: expect.any(Date) }),
    );
  });

  it('still reports a missing type as not found, not in use', async () => {
    repo.findDocumentTypeById.mockResolvedValue(null);

    await expect(deleteDocumentType(7n, ACTOR)).rejects.toMatchObject({
      messageKey: 'masters.documentTypeNotFound',
    });
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npm test -- masters.documentTypes`
Expected: FAIL — `countDocumentTypeUsage` is not exported by the repository.

- [ ] **Step 3: Add the repository count**

Append to the document-types section of `backend/src/modules/masters/masters.repository.ts`:

```ts
/**
 * How many live files point at this document type, across both checklists.
 *
 * Soft-deleted files do not count — a removed upload is not a reason to keep a
 * type on the books. Soft-deleted *types* are irrelevant here; the caller has
 * already established the type exists.
 */
export const countDocumentTypeUsage = async (db: Db, id: bigint): Promise<number> => {
  const [applications, members] = await Promise.all([
    db.applicationDocument.count({ where: { document_type_id: id, deletedAt: null } }),
    db.memberDocument.count({ where: { document_type_id: id, deletedAt: null } }),
  ]);

  return applications + members;
};
```

> **Ordering note:** `applicationDocument.document_type_id` does not exist until
> Task 3. Until then this file will not typecheck. That is deliberate — Task 2
> and Task 3 land together. Run Task 3 immediately after this step, then return
> here for Step 5. If you are executing tasks in isolation, do Task 3's Steps 1-4
> now.

- [ ] **Step 4: Add the guard to the service**

In `backend/src/modules/masters/masters.service.ts`, replace the body of
`deleteDocumentType` (currently lines 559-577):

```ts
export const deleteDocumentType = async (id: bigint, actor: Actor) => {
  const existing = await repo.findDocumentTypeById(prisma, id);
  if (!existing) throw notFound('masters.documentTypeNotFound');

  /*
    Refuse while anything points at it.

    This guard is the whole reason the ApplicationDocuments foreign key can be
    restored. Retiring a type out from under a live application is what broke
    registration on 2026-08-24 and caused the FK to be replaced by an enum;
    `onDelete: Restrict` does not help, because a soft delete is an UPDATE and
    Postgres never sees a violation. `is_active = false` is the correct way to
    stop offering a type that has already been used.
  */
  if ((await repo.countDocumentTypeUsage(prisma, id)) > 0) {
    throw conflict('masters.documentTypeInUse');
  }

  await prisma.$transaction(async (tx) => {
    await repo.updateDocumentType(tx, id, { deletedAt: new Date(), is_active: false });

    await writeAudit(tx, {
      ...audited(actor),
      action: AUDIT_ACTIONS.DOCUMENT_TYPE_DELETED,
      entityName: 'DocumentTypes',
      entityId: id,
      before: { code: existing.code, name: existing.name },
    });
  });
};
```

- [ ] **Step 5: Add the message**

In `backend/src/locales/en.json`, in the `masters` object beside
`documentTypeNotFound`:

```json
    "documentTypeInUse": "This document type cannot be deleted — files have already been uploaded against it. Turn off \"Offered for new uploads\" to retire it instead.",
```

- [ ] **Step 6: Run to verify it passes**

Run: `cd backend && npm test -- masters.documentTypes`
Expected: PASS, 3 tests.

- [ ] **Step 7: Checkpoint**

Run: `cd backend && npm run typecheck && npm run lint`
Expected: baseline errors only (assumes Task 3 is applied).
*(git: `git commit -am "fix(masters): refuse to delete a document type still in use"`)*

---

### Task 3: Schema, migration and seed

**Files:**
- Modify: `backend/prisma/schema/membership.prisma` (new enums, `sides` column)
- Modify: `backend/prisma/schema/application.prisma:15-19` (drop enum, swap column to FK)
- Modify: `backend/prisma/schema/member.prisma` (`side` column)
- Create: `backend/prisma/migrations/<timestamp>_m5_dynamic_document_types_and_sides/migration.sql`
- Create: `backend/prisma/seed/documentTypes.ts`
- Modify: `backend/prisma/seed.ts`

**Interfaces:**
- Consumes: nothing
- Produces: Prisma enums `DocumentSides` (`SINGLE`, `FRONT_AND_BACK`) and `DocumentSide` (`SINGLE`, `FRONT`, `BACK`, `COMBINED`); `DocumentType.sides`; `ApplicationDocument.document_type_id` + `.side` + relation `document_type`; `MemberDocument.side`; `seedDocumentTypes(prisma)`.

- [ ] **Step 1: Add the enums and the `sides` column**

In `backend/prisma/schema/membership.prisma`, directly after the
`DocumentAppliesTo` enum (line 27):

```prisma
/// How many faces of a physical document must be collected. A certificate is one
/// file; an ID card carries its address or signature on the reverse.
enum DocumentSides {
  /// One file is the whole document.
  SINGLE

  /// Two files — an applicant who supplies only one has not supplied the document.
  FRONT_AND_BACK
}

/// Which face an uploaded file is. Stored on every upload so a reviewer can accept
/// one side and reject the other without the member re-supplying both.
enum DocumentSide {
  /// The only file for a SINGLE type.
  SINGLE

  FRONT

  BACK

  /// One multi-page PDF carrying both faces of a FRONT_AND_BACK type.
  COMBINED
}
```

In `model DocumentType`, after `is_required` (line 221):

```prisma
  /// Whether this document is collected as one file or as a front and a back.
  /// Existing rows default to SINGLE, which is how every type behaved before M5.
  sides DocumentSides @default(SINGLE)
```

- [ ] **Step 2: Swap the application column to a foreign key**

In `backend/prisma/schema/application.prisma`, delete the
`RegistrationDocumentType` enum (lines 12-19, including its `///` comment).

In `model ApplicationDocument`, replace lines 275-277:

```prisma
  /// FK to DocumentTypes.id — which checklist requirement this file satisfies.
  /// ON DELETE RESTRICT, backed by an application-level in-use guard on the master
  /// (a soft delete is an UPDATE, which a foreign key cannot catch).
  document_type_id BigInt

  /// Which face of the document this file is. SINGLE for a one-file type.
  side DocumentSide @default(SINGLE)
```

In the relations block, beside the `application` relation:

```prisma
  /// The checklist requirement this file satisfies.
  document_type DocumentType @relation(fields: [document_type_id], references: [id], onDelete: Restrict, onUpdate: Cascade)
```

Replace the index:

```prisma
  @@index([application_id, document_type_id])
```

- [ ] **Step 3: Add `side` to member documents**

In `backend/prisma/schema/member.prisma`, in `model MemberDocument` after
`document_type_id` (line 301):

```prisma
  /// Which face of the document this file is. SINGLE for a one-file type.
  side DocumentSide @default(SINGLE)
```

- [ ] **Step 4: Add the back-relation on DocumentType**

In `model DocumentType` (`membership.prisma`), beside the existing
`member_documents` relation, add:

```prisma
  /// Evidence uploaded against this requirement during registration.
  application_documents ApplicationDocument[]
```

Run `npx prisma format` in `backend/` — if `member_documents` does not exist
under that name, use whatever the file already calls it and match the style.

- [ ] **Step 5: Create the migration shell**

```bash
cd backend
npm run prisma:migrate:create -- --name m5_dynamic_document_types_and_sides
```

This writes a `migration.sql` Prisma generated. **Replace its entire contents**
with Step 6 — Prisma's generated version drops and recreates the column and
would lose every existing upload's type.

- [ ] **Step 6: Write the migration SQL**

```sql
-- Reverses 20260824130000_m5_application_document_fixed_kyc_type.
--
-- That migration replaced the DocumentTypes foreign key with an enum because a
-- soft-deleted type broke registration. The foreign key was never the fault: the
-- master's delete had no in-use guard (masters.service.ts). The guard now exists,
-- so the association can configure its own checklist again — which is the point
-- of this change — without the outage that forced the enum.

-- CreateEnum
CREATE TYPE "DocumentSides" AS ENUM ('SINGLE', 'FRONT_AND_BACK');
CREATE TYPE "DocumentSide" AS ENUM ('SINGLE', 'FRONT', 'BACK', 'COMBINED');

-- AlterTable: the master gains its sides setting. Every existing row is SINGLE,
-- which is exactly how it behaved before this migration.
ALTER TABLE "DocumentTypes" ADD COLUMN "sides" "DocumentSides" NOT NULL DEFAULT 'SINGLE';
COMMENT ON COLUMN "DocumentTypes"."sides" IS 'Whether this document is collected as one file or as a front and a back.';

-- AlterTable: every uploaded file records which face it is.
ALTER TABLE "ApplicationDocuments" ADD COLUMN "side" "DocumentSide" NOT NULL DEFAULT 'SINGLE';
COMMENT ON COLUMN "ApplicationDocuments"."side" IS 'Which face of the document this file is. SINGLE for a one-file type.';

ALTER TABLE "MemberDocuments" ADD COLUMN "side" "DocumentSide" NOT NULL DEFAULT 'SINGLE';
COMMENT ON COLUMN "MemberDocuments"."side" IS 'Which face of the document this file is. SINGLE for a one-file type.';

-- The three registration types become rows. Idempotent: rows an admin created by
-- hand keep their ids, their guidance and their edits.
--
-- applies_to = APPLICATION, not BOTH. Registration behaviour is reproduced
-- exactly and no existing member's profile silently grows three new
-- requirements. An admin can widen any of them from screen A-12 afterwards.
INSERT INTO "DocumentTypes"
  ("code", "name", "description", "applies_to", "is_required", "sides",
   "max_size_mb", "allowed_mime", "display_order", "is_active", "createdAt", "updatedAt")
VALUES
  ('GST_CERTIFICATE', 'GST Certificate', 'A clear scan or PDF of the GST registration certificate.',
   'APPLICATION', true, 'SINGLE', 10, ARRAY['application/pdf','image/jpeg','image/png'], 1, true, NOW(), NOW()),
  ('PAN_DOCUMENT', 'PAN Document', 'The company PAN card, or the proprietor''s PAN for a proprietorship.',
   'APPLICATION', true, 'SINGLE', 10, ARRAY['application/pdf','image/jpeg','image/png'], 2, true, NOW(), NOW()),
  ('TRADE_LICENCE', 'Trade Licence', 'The current trade licence issued by your local authority.',
   'APPLICATION', true, 'SINGLE', 10, ARRAY['application/pdf','image/jpeg','image/png'], 3, true, NOW(), NOW())
ON CONFLICT ("code") DO NOTHING;

-- A type that was soft-deleted but is named by the enum must come back, or the
-- backfill below cannot resolve its files. This is the 2026-08-24 failure, undone.
UPDATE "DocumentTypes"
   SET "deletedAt" = NULL, "is_active" = true
 WHERE "code" IN ('GST_CERTIFICATE', 'PAN_DOCUMENT', 'TRADE_LICENCE')
   AND "deletedAt" IS NOT NULL;

-- AlterTable: nullable first, backfill, then tighten.
ALTER TABLE "ApplicationDocuments" ADD COLUMN "document_type_id" BIGINT;

UPDATE "ApplicationDocuments" ad
   SET "document_type_id" = dt."id"
  FROM "DocumentTypes" dt
 WHERE dt."code" = ad."document_type"::text;

-- Fail loudly. A half-migrated evidence table is worse than a failed deploy: the
-- applicant would appear not to have supplied a document they did supply.
DO $$
DECLARE orphaned INT;
BEGIN
  SELECT COUNT(*) INTO orphaned FROM "ApplicationDocuments" WHERE "document_type_id" IS NULL;
  IF orphaned > 0 THEN
    RAISE EXCEPTION 'Migration aborted: % ApplicationDocuments rows have no matching DocumentTypes.code', orphaned;
  END IF;
END $$;

ALTER TABLE "ApplicationDocuments" ALTER COLUMN "document_type_id" SET NOT NULL;
COMMENT ON COLUMN "ApplicationDocuments"."document_type_id" IS 'FK to DocumentTypes.id - which checklist requirement this file satisfies.';

ALTER TABLE "ApplicationDocuments"
  ADD CONSTRAINT "ApplicationDocuments_document_type_id_fkey"
  FOREIGN KEY ("document_type_id") REFERENCES "DocumentTypes"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

DROP INDEX IF EXISTS "ApplicationDocuments_application_id_document_type_idx";
CREATE INDEX "ApplicationDocuments_application_id_document_type_id_idx"
  ON "ApplicationDocuments"("application_id", "document_type_id");

ALTER TABLE "ApplicationDocuments" DROP COLUMN "document_type";
DROP TYPE "RegistrationDocumentType";
```

- [ ] **Step 7: Apply it**

```bash
cd backend
npx prisma migrate dev
npm run prisma:generate
```

Expected: the migration applies with no error. If the `RAISE EXCEPTION` fires,
some `ApplicationDocuments` row has a type code with no matching row — add that
code to the `INSERT` above (do **not** loosen the guard) and re-run.

- [ ] **Step 8: Verify the data**

```bash
cd backend && npm run prisma:status && npm run db:check-comments
```

Expected: `prisma migrate status` clean, `db:check-comments` returns **zero
rows** (every new column has a comment — a Sentinel gate, ADR-013).

- [ ] **Step 9: Write the seed**

Create `backend/prisma/seed/documentTypes.ts`:

```ts
import type { PrismaClient } from '@prisma/client';

/**
 * The three KYC documents registration has always asked for.
 *
 * Seeded rather than hardcoded (M5): the association configures its own checklist
 * from screen A-12 now, and these three are the starting point rather than the
 * whole list. Upserted by code so a re-run never duplicates them and never
 * overwrites an admin's edits to name, guidance or size.
 */
const DOCUMENT_TYPES = [
  {
    code: 'GST_CERTIFICATE',
    name: 'GST Certificate',
    description: 'A clear scan or PDF of the GST registration certificate.',
    display_order: 1,
  },
  {
    code: 'PAN_DOCUMENT',
    name: 'PAN Document',
    description: "The company PAN card, or the proprietor's PAN for a proprietorship.",
    display_order: 2,
  },
  {
    code: 'TRADE_LICENCE',
    name: 'Trade Licence',
    description: 'The current trade licence issued by your local authority.',
    display_order: 3,
  },
] as const;

export const seedDocumentTypes = async (prisma: PrismaClient): Promise<void> => {
  for (const type of DOCUMENT_TYPES) {
    await prisma.documentType.upsert({
      where: { code: type.code },
      // Nothing on update: an admin who renamed "Trade Licence" or widened its
      // size ceiling keeps that change through the next deploy.
      update: {},
      create: {
        ...type,
        applies_to: 'APPLICATION',
        is_required: true,
        sides: 'SINGLE',
        max_size_mb: 10,
        allowed_mime: ['application/pdf', 'image/jpeg', 'image/png'],
        is_active: true,
      },
    });
  }
};

export default seedDocumentTypes;
```

- [ ] **Step 10: Wire the seed in**

In `backend/prisma/seed.ts`, import and call `seedDocumentTypes` alongside the
other module seeds, before any seed that could reference a document type. Match
the file's existing call style exactly.

- [ ] **Step 11: Run the seed**

```bash
cd backend && npm run prisma:seed
```

Expected: completes; re-running it a second time also completes with no
duplicate-key error.

- [ ] **Step 12: Checkpoint**

Run: `cd backend && npm run typecheck`
Expected: `application.service.ts` and `application.repository.ts` now report
**more** errors than baseline — `document_type` no longer exists on the model.
That is correct and expected; Tasks 4-7 fix each one. Note the exact list before
moving on.
*(git: `git commit -am "feat(db): document type FK and front/back sides"`)*

---

### Task 4: The checklist service

One function answers "which documents does this surface ask for". Every caller
uses it; nothing re-implements the filter.

**Files:**
- Create: `backend/src/modules/masters/masters.checklist.ts`
- Create: `backend/src/modules/masters/masters.checklist.test.ts`

**Interfaces:**
- Consumes: `DocumentSidesValue` from `@modules/document/document.sides` (Task 1)
- Produces:
  - `type ChecklistItem = { id: bigint; code: string; name: string; description: string | null; is_required: boolean; sides: DocumentSidesValue; max_size_mb: number; allowed_mime: string[]; display_order: number }`
  - `checklistFor(surface: 'APPLICATION' | 'MEMBER'): Promise<ChecklistItem[]>`
  - `findTypeForUpload(code: string): Promise<ChecklistItem | null>` — active types only, for accepting a new file
  - `findTypeById(id: bigint): Promise<ChecklistItem | null>` — **ignores `deletedAt` and `is_active`**, for resolving a file already uploaded

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/masters/masters.checklist.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

const findMany = vi.fn();
const findFirst = vi.fn();

vi.mock('@db/prisma', () => ({
  prisma: { documentType: { findMany: (...a: unknown[]) => findMany(...a), findFirst: (...a: unknown[]) => findFirst(...a) } },
}));

const { checklistFor, findTypeById, findTypeForUpload } = await import(
  '@modules/masters/masters.checklist'
);

const ROW = {
  id: 4n,
  code: 'AADHAAR_CARD',
  name: 'Aadhaar Card',
  description: null,
  is_required: true,
  sides: 'FRONT_AND_BACK',
  max_size_mb: 10,
  allowed_mime: ['image/png'],
  display_order: 2,
};

describe('checklistFor', () => {
  beforeEach(() => findMany.mockResolvedValue([ROW]));

  it('asks for APPLICATION and BOTH rows on the registration surface', async () => {
    await checklistFor('APPLICATION');

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          deletedAt: null,
          is_active: true,
          applies_to: { in: ['APPLICATION', 'BOTH'] },
        }),
      }),
    );
  });

  it('asks for MEMBER and BOTH rows on the profile surface', async () => {
    await checklistFor('MEMBER');

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ applies_to: { in: ['MEMBER', 'BOTH'] } }),
      }),
    );
  });

  it('returns the row shape the API and the forms render', async () => {
    await expect(checklistFor('APPLICATION')).resolves.toEqual([
      expect.objectContaining({ code: 'AADHAAR_CARD', sides: 'FRONT_AND_BACK', is_required: true }),
    ]);
  });
});

describe('findTypeForUpload', () => {
  it('refuses a retired type for a new upload', async () => {
    findFirst.mockResolvedValue(null);

    await expect(findTypeForUpload('OLD_CODE')).resolves.toBeNull();
    expect(findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { code: 'OLD_CODE', deletedAt: null, is_active: true } }),
    );
  });
});

describe('findTypeById', () => {
  it('resolves a retired type, because a file already points at it', async () => {
    findFirst.mockResolvedValue(ROW);

    await findTypeById(4n);

    expect(findFirst).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 4n } }));
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npm test -- masters.checklist`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

Create `backend/src/modules/masters/masters.checklist.ts`:

```ts
import { prisma } from '@db/prisma';
import type { DocumentSidesValue } from '@modules/document/document.sides';

/**
 * Which documents each surface asks for.
 *
 * The single source of that answer (spec §5.1). Registration, the member profile,
 * the completeness gate and the approve guard all read it, so "what is on the
 * checklist" is decided in one place and an admin's edit reaches all four at once.
 */

export interface ChecklistItem {
  id: bigint;
  code: string;
  name: string;
  description: string | null;
  is_required: boolean;
  sides: DocumentSidesValue;
  max_size_mb: number;
  allowed_mime: string[];
  display_order: number;
}

const SELECT = {
  id: true,
  code: true,
  name: true,
  description: true,
  is_required: true,
  sides: true,
  max_size_mb: true,
  allowed_mime: true,
  display_order: true,
} as const;

const SURFACES = {
  APPLICATION: ['APPLICATION', 'BOTH'],
  MEMBER: ['MEMBER', 'BOTH'],
} as const;

export type ChecklistSurface = keyof typeof SURFACES;

/** Active rows for one surface, in the order the admin arranged them. */
export const checklistFor = async (surface: ChecklistSurface): Promise<ChecklistItem[]> =>
  (await prisma.documentType.findMany({
    where: { deletedAt: null, is_active: true, applies_to: { in: [...SURFACES[surface]] } },
    orderBy: [{ display_order: 'asc' }, { name: 'asc' }],
    select: SELECT,
  })) as ChecklistItem[];

/**
 * The type a NEW upload names. Retired and deactivated types are refused — the
 * association has stopped asking for them.
 */
export const findTypeForUpload = async (code: string): Promise<ChecklistItem | null> =>
  (await prisma.documentType.findFirst({
    where: { code, deletedAt: null, is_active: true },
    select: SELECT,
  })) as ChecklistItem | null;

/**
 * The type an EXISTING file points at. Deliberately unfiltered.
 *
 * A file already uploaded must always resolve its type, even one since retired,
 * or the member's own document list breaks when an admin tidies the master. This
 * is the failure that caused the foreign key to be dropped on 2026-08-24
 * (spec §4.4 item 2) — do not add a `deletedAt` filter here.
 */
export const findTypeById = async (id: bigint): Promise<ChecklistItem | null> =>
  (await prisma.documentType.findFirst({ where: { id }, select: SELECT })) as ChecklistItem | null;
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd backend && npm test -- masters.checklist`
Expected: PASS, 5 tests.

- [ ] **Step 5: Checkpoint**

Run: `cd backend && npm run lint`
*(git: `git commit -am "feat(masters): single-source document checklist"`)*

---

### Task 5: Upload validation reads the master

**Files:**
- Modify: `backend/src/modules/document/document.service.ts:355-420` (delete `REGISTRATION_DOCUMENT_RULES`, `isRegistrationDocumentType`; rewrite `validateApplicationFileBuffer`, `storeApplicationFile`, `createApplicationDocumentRow`)
- Modify: `backend/src/modules/document/document.service.ts:172-215` (`checklistForMember` routes through Task 4 and carries `sides`/`side`)
- Modify: `backend/src/modules/document/document.service.ts:50-140` (member upload records `side`)
- Modify: `backend/src/modules/member/member.controller.ts:229`

**Interfaces:**
- Consumes: `findTypeForUpload`, `findTypeById`, `ChecklistItem` (Task 4); `sideForUpload` (Task 1)
- Produces:
  - `validateApplicationFileBuffer(code: string, buffer: Buffer, declaredMime: string, requestedSide?: DocumentSideValue): Promise<{ type: ChecklistItem; side: DocumentSideValue; actualMime: string }>`
  - `StoredApplicationFile` gains `document_type_id: bigint` and `side: DocumentSideValue`, and **loses** `documentType: RegistrationDocumentType`
  - `checklistForMember` items gain `sides` and each `document` gains `side`

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/document/document.upload.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

const checklist = vi.hoisted(() => ({ findTypeForUpload: vi.fn(), findTypeById: vi.fn() }));
vi.mock('@modules/masters/masters.checklist', () => checklist);
vi.mock('@db/prisma', () => ({ prisma: {} }));

const { validateApplicationFileBuffer } = await import('@modules/document/document.service');

// A one-byte-per-pixel PNG header is enough for the sniffer.
const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex');
const PDF = Buffer.from('255044462d312e340a', 'hex');

const TYPE = {
  id: 9n,
  code: 'AADHAAR_CARD',
  name: 'Aadhaar Card',
  description: null,
  is_required: true,
  sides: 'FRONT_AND_BACK' as const,
  max_size_mb: 10,
  allowed_mime: ['application/pdf', 'image/png'],
  display_order: 1,
};

describe('validateApplicationFileBuffer', () => {
  beforeEach(() => checklist.findTypeForUpload.mockResolvedValue(TYPE));

  it('rejects a code with no active type', async () => {
    checklist.findTypeForUpload.mockResolvedValue(null);

    await expect(validateApplicationFileBuffer('NOPE', PNG, 'image/png')).rejects.toMatchObject({
      messageKey: 'masters.documentTypeNotFound',
    });
  });

  it('rejects a file above the type’s own ceiling', async () => {
    checklist.findTypeForUpload.mockResolvedValue({ ...TYPE, max_size_mb: 1 });
    const big = Buffer.concat([PNG, Buffer.alloc(2 * 1024 * 1024)]);

    await expect(validateApplicationFileBuffer('AADHAAR_CARD', big, 'image/png')).rejects.toMatchObject({
      messageKey: 'document.tooLarge',
    });
  });

  it('rejects a mime the type does not allow', async () => {
    checklist.findTypeForUpload.mockResolvedValue({ ...TYPE, allowed_mime: ['application/pdf'] });

    await expect(validateApplicationFileBuffer('AADHAAR_CARD', PNG, 'image/png')).rejects.toMatchObject({
      messageKey: 'document.unsupportedType',
    });
  });

  it('stores an image against a two-sided type as the face requested', async () => {
    await expect(validateApplicationFileBuffer('AADHAAR_CARD', PNG, 'image/png', 'BACK')).resolves.toMatchObject({
      side: 'BACK',
      type: expect.objectContaining({ id: 9n }),
    });
  });

  it('stores a PDF against a two-sided type as both faces', async () => {
    await expect(validateApplicationFileBuffer('AADHAAR_CARD', PDF, 'application/pdf', 'FRONT')).resolves.toMatchObject({
      side: 'COMBINED',
    });
  });

  it('ignores a requested face on a single-sided type', async () => {
    checklist.findTypeForUpload.mockResolvedValue({ ...TYPE, sides: 'SINGLE' as const });

    await expect(validateApplicationFileBuffer('AADHAAR_CARD', PNG, 'image/png', 'BACK')).resolves.toMatchObject({
      side: 'SINGLE',
    });
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npm test -- document.upload`
Expected: FAIL — the function still takes a hardcoded code and returns `documentType`.

- [ ] **Step 3: Delete the hardcoded rules**

In `backend/src/modules/document/document.service.ts`, delete
`REGISTRATION_DOCUMENT_RULES` and `isRegistrationDocumentType` entirely (lines
355-372, including the block comment above them), and remove
`RegistrationDocumentType` from the `@prisma/client` import on line 1.

- [ ] **Step 4: Rewrite the validator**

```ts
/**
 * Shared validation for application uploads — bytes only, no persistence.
 *
 * Limits come from the document type row, not from a constant: the association
 * configures its own checklist from screen A-12 (M5), so a size ceiling raised in
 * the admin takes effect on the next upload with no deploy.
 *
 * Magic-byte sniffing is unchanged. A client-declared Content-Type is not
 * evidence (file-storage.md §3), and the closed MIME allowlist on the master
 * still means an admin cannot admit `image/svg+xml`.
 */
export const validateApplicationFileBuffer = async (
  documentTypeCode: string,
  buffer: Buffer,
  declaredMime: string,
  requestedSide?: DocumentSideValue,
): Promise<{ type: ChecklistItem; side: DocumentSideValue; actualMime: string }> => {
  const type = await findTypeForUpload(documentTypeCode);
  if (!type) throw notFound('masters.documentTypeNotFound');

  const maxBytes = type.max_size_mb * 1024 * 1024;
  if (buffer.length > maxBytes) {
    throw invalid('document.tooLarge', {
      replacements: { max_size_mb: String(type.max_size_mb) },
      details: { max_size_mb: type.max_size_mb, actual_bytes: buffer.length },
    });
  }

  if (buffer.length === 0) throw invalid('document.empty');

  if (!matchesAllowedMime(buffer, type.allowed_mime)) {
    throw invalid('document.unsupportedType', {
      replacements: { allowed: type.allowed_mime.join(', ') },
      details: {
        declared: declaredMime,
        detected: sniffMime(buffer) ?? 'unrecognised',
        allowed: type.allowed_mime,
      },
    });
  }

  const actualMime = sniffMime(buffer) as string;

  return { type, side: sideForUpload(type.sides, requestedSide, actualMime), actualMime };
};
```

Add at the top of the file:

```ts
import { type ChecklistItem, findTypeById, findTypeForUpload } from '@modules/masters/masters.checklist';
import { type DocumentSideValue, sideForUpload } from '@modules/document/document.sides';
```

- [ ] **Step 5: Carry the type id and side through storage**

Change `StoredApplicationFile` to:

```ts
export interface StoredApplicationFile {
  document_type_id: bigint;
  document_type_code: string;
  side: DocumentSideValue;
  file_path: string;
  original_name: string;
  mime_type: string;
  size_bytes: bigint;
  checksum_sha256: string;
}
```

In `storeApplicationFile`, accept an optional `requestedSide`, pass it to the
validator, build the storage path from `type.code` (unchanged shape), and return
`document_type_id: type.id`, `document_type_code: type.code`, `side`.

In `createApplicationDocumentRow`, write `document_type_id: stored.document_type_id`
and `side: stored.side` instead of `document_type: stored.documentType`.

- [ ] **Step 6: Give the member checklist the same shape**

In `checklistForMember`, replace the inline `prisma.documentType.findMany` with
`checklistFor('MEMBER')`, add `sides: type.sides` to each item, and change the
"latest upload" map so it keys on `${document_type_id}:${side}` rather than
`document_type_id` — a two-sided type has a newest front *and* a newest back.

Replace the `satisfied` calculation with `isSatisfied` from Task 1, evaluated
over the non-rejected sides present for each required type.

Add `side: true` to the `include`/`select` in `listForMember`.

- [ ] **Step 7: Pass the side through the member upload**

`member.controller.ts:229` sends `documentTypeCode: code`. Add
`side: req.body.side` (validated by a zod `z.enum(['FRONT','BACK']).optional()`
in the member module's types) and thread it to the service.

- [ ] **Step 8: Run to verify it passes**

Run: `cd backend && npm test -- document.upload`
Expected: PASS, 6 tests.

- [ ] **Step 9: Checkpoint**

Run: `cd backend && npm run lint`
*(git: `git commit -am "feat(document): read upload rules from the master, record side"`)*

---

### Task 6: Completeness and the approval guard

**Files:**
- Modify: `backend/src/modules/application/approval.engine.ts:271-305` (`checkCompleteness`)
- Modify: `backend/src/modules/application/application.repository.ts:290-336` (delete `listRequiredDocumentTypes`; rewrite `listApplicationDocuments` and the unverified count)
- Modify: `backend/src/modules/application/application.service.ts:212-224` (`completeness`)
- Create: `backend/src/modules/application/approval.completeness.test.ts`

**Interfaces:**
- Consumes: `ChecklistItem`, `checklistFor` (Task 4); `missingSides`, `describeSide` (Task 1)
- Produces:
  - `type MissingDocument = { code: string; name: string; side: DocumentSideValue; label: string }`
  - `checkCompleteness(application, required: ChecklistItem[], supplied: Array<{ code: string; side: DocumentSideValue }>): CompletenessResult` where `missingDocuments: MissingDocument[]`
  - `countUnverifiedRequiredDocuments(db, applicationId): Promise<number>` — counts `(type, side)` pairs

**Breaking change:** `missingDocuments` was `string[]` (codes). It is now an array
of objects. Task 11 and Task 12 update the customer app to match.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/application/approval.completeness.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { checkCompleteness } from '@modules/application/approval.engine';

const type = (over: Partial<{ code: string; name: string; sides: 'SINGLE' | 'FRONT_AND_BACK'; is_required: boolean }> = {}) => ({
  id: 1n,
  code: 'PAN_DOCUMENT',
  name: 'PAN Document',
  description: null,
  is_required: true,
  sides: 'SINGLE' as const,
  max_size_mb: 10,
  allowed_mime: ['application/pdf'],
  display_order: 1,
  ...over,
});

const APPLICATION = { company_name: 'Acme Exports', category_id: 3n };

describe('checkCompleteness', () => {
  it('is complete when the single required document is supplied', () => {
    const result = checkCompleteness(APPLICATION, [type()], [{ code: 'PAN_DOCUMENT', side: 'SINGLE' }]);

    expect(result.complete).toBe(true);
    expect(result.missingDocuments).toEqual([]);
  });

  it('names an entirely missing document', () => {
    const result = checkCompleteness(APPLICATION, [type()], []);

    expect(result.complete).toBe(false);
    expect(result.missingDocuments).toEqual([
      { code: 'PAN_DOCUMENT', name: 'PAN Document', side: 'SINGLE', label: 'PAN Document' },
    ]);
  });

  it('names only the missing face of a two-sided document', () => {
    const aadhaar = type({ code: 'AADHAAR_CARD', name: 'Aadhaar Card', sides: 'FRONT_AND_BACK' });
    const result = checkCompleteness(APPLICATION, [aadhaar], [{ code: 'AADHAAR_CARD', side: 'FRONT' }]);

    expect(result.missingDocuments).toEqual([
      { code: 'AADHAAR_CARD', name: 'Aadhaar Card', side: 'BACK', label: 'Aadhaar Card (back)' },
    ]);
  });

  it('accepts a combined PDF for a two-sided document', () => {
    const aadhaar = type({ code: 'AADHAAR_CARD', name: 'Aadhaar Card', sides: 'FRONT_AND_BACK' });
    const result = checkCompleteness(APPLICATION, [aadhaar], [{ code: 'AADHAAR_CARD', side: 'COMBINED' }]);

    expect(result.complete).toBe(true);
  });

  it('never blocks on an optional document', () => {
    const cheque = type({ code: 'CANCELLED_CHEQUE', is_required: false });
    const result = checkCompleteness(APPLICATION, [cheque], []);

    expect(result.complete).toBe(true);
    expect(result.missingDocuments).toEqual([]);
  });

  it('still reports missing fields alongside missing documents', () => {
    const result = checkCompleteness({ company_name: '', category_id: null }, [type()], []);

    expect(result.missingFields).toEqual(['company_name', 'category_id']);
    expect(result.missingDocuments).toHaveLength(1);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npm test -- approval.completeness`
Expected: FAIL — `checkCompleteness` still takes two string arrays.

- [ ] **Step 3: Rewrite `checkCompleteness`**

Replace `approval.engine.ts` lines 274-305:

```ts
export interface MissingDocument {
  code: string;
  name: string;
  side: DocumentSideValue;
  /** How it reads in a sentence — "Aadhaar Card (back)". */
  label: string;
}

export interface CompletenessResult {
  complete: boolean;
  missingFields: string[];
  missingDocuments: MissingDocument[];
}

/**
 * Is this application submittable?
 *
 * Returns everything that is missing rather than the first problem: a form that
 * rejects one field at a time turns submission into a guessing game
 * (ux-principles.md §5).
 *
 * Documents are compared as (type, face) pairs, not as codes. A two-sided type
 * with only its front uploaded is as incomplete as one with nothing, and the
 * applicant is told exactly which half is owed — the whole point of `sides`.
 *
 * Optional types are never counted. They are on the checklist so the applicant
 * CAN supply them, not so they must.
 */
export const checkCompleteness = (
  application: Record<string, unknown>,
  required: ChecklistItem[],
  supplied: Array<{ code: string; side: DocumentSideValue }>,
): CompletenessResult => {
  const missingFields = REQUIRED_FIELDS.filter((field) => {
    const value = application[field];

    return value === null || value === undefined || value === '';
  });

  const byCode = new Map<string, DocumentSideValue[]>();
  for (const item of supplied) {
    byCode.set(item.code, [...(byCode.get(item.code) ?? []), item.side]);
  }

  const missingDocuments = required
    .filter((type) => type.is_required)
    .flatMap((type) =>
      missingSides(type.sides, byCode.get(type.code) ?? []).map((side) => ({
        code: type.code,
        name: type.name,
        side,
        label: describeSide(type.name, side),
      })),
    );

  return {
    complete: missingFields.length === 0 && missingDocuments.length === 0,
    missingFields: [...missingFields],
    missingDocuments,
  };
};
```

Import at the top of `approval.engine.ts`:

```ts
import { describeSide, type DocumentSideValue, missingSides } from '@modules/document/document.sides';
import type { ChecklistItem } from '@modules/masters/masters.checklist';
```

- [ ] **Step 4: Update `incompleteError`**

Its `details` currently passes `result.missingDocuments` straight through. Change
the documents entry to `result.missingDocuments.map((d) => d.label)` so the error
payload stays a list of readable strings.

- [ ] **Step 5: Rewrite the repository helpers**

Delete `listRequiredDocumentTypes` (line 298) and its comment block, and the
`REGISTRATION_KYC_CODES` import on line 4.

`listApplicationDocuments` gains the type and orders by it:

```ts
export const listApplicationDocuments = (db: Db, applicationId: bigint) =>
  db.applicationDocument.findMany({
    where: { application_id: applicationId, deletedAt: null },
    orderBy: [{ document_type_id: 'asc' }, { side: 'asc' }, { version: 'desc' }],
    include: {
      // Unfiltered on purpose — a file must resolve its type even if that type
      // was later retired (spec §4.4 item 2).
      document_type: { select: { id: true, code: true, name: true, sides: true, is_required: true } },
    },
  });
```

Rewrite the unverified count (lines ~310-336) to key its `latest` map on
`${document_type_id}:${side}` and to count, for every **required active** type,
each face whose newest file is not `VERIFIED`:

```ts
/**
 * How many required KYC faces are not yet VERIFIED.
 *
 * The number the approve guard refuses on and the number its message names
 * (spec D-7). Counted over the LATEST version of each required (type, face), so a
 * two-sided document with a verified front and a rejected back still blocks.
 */
export const countUnverifiedRequiredDocuments = async (
  db: Db,
  applicationId: bigint,
): Promise<number> => {
  const required = (await checklistFor('APPLICATION')).filter((type) => type.is_required);
  const documents = await listApplicationDocuments(db, applicationId);

  const latest = new Map<string, string>();
  for (const doc of documents) {
    const key = `${doc.document_type_id}:${doc.side}`;
    if (!latest.has(key)) latest.set(key, doc.verification_status);
  }

  return required.reduce((count, type) => {
    // A COMBINED PDF stands for both faces, so its single verdict decides both.
    const combined = latest.get(`${type.id}:COMBINED`);
    if (combined) return count + (combined === 'VERIFIED' ? 0 : 1);

    const outstanding = requiredSides(type.sides).filter(
      (side) => latest.get(`${type.id}:${side}`) !== 'VERIFIED',
    );

    return count + outstanding.length;
  }, 0);
};
```

Keep the existing exported name so callers do not change; if the current name
differs, keep the current one and adapt the body.

- [ ] **Step 6: Update the service caller**

`application.service.ts:216-223` becomes:

```ts
export const completeness = async (applicationId: bigint, userId: bigint) => {
  const application = await assertOwnedAndEditable(applicationId, userId);
  const [required, documents] = await Promise.all([
    checklistFor('APPLICATION'),
    repo.listApplicationDocuments(prisma, applicationId),
  ]);

  return engine.checkCompleteness(
    application as unknown as Record<string, unknown>,
    required,
    documents
      .filter((doc) => doc.verification_status !== 'REJECTED')
      .map((doc) => ({ code: doc.document_type.code, side: doc.side as DocumentSideValue })),
  );
};
```

- [ ] **Step 7: Run to verify it passes**

Run: `cd backend && npm test`
Expected: PASS, all suites. 6 new tests in this file.

- [ ] **Step 8: Checkpoint**

Run: `cd backend && npm run typecheck`
Expected: the application-module errors from Task 3 Step 12 are gone; only the 4
baseline errors plus any in `auth`/`document` that Tasks 7-8 fix.
*(git: `git commit -am "feat(application): completeness and approval by document face"`)*

---

### Task 7: The public checklist endpoint

The registration form must render before anyone has an account, so it cannot use
`GET /members/me/documents`.

**Files:**
- Modify: `backend/src/constant/endPoints.constant.ts`
- Modify: `backend/src/modules/masters/masters.controller.ts` (new handler)
- Modify: `backend/src/modules/masters/masters.routes.ts` (public router)

**Interfaces:**
- Consumes: `checklistFor` (Task 4)
- Produces: `GET /api/v1/public/document-checklist` → `{ items: Array<{ code, name, description, is_required, sides, max_size_mb, allowed_mime, display_order }> }`. No ids — an anonymous caller has no use for a primary key.

- [ ] **Step 1: Add the endpoint constant**

In `backend/src/constant/endPoints.constant.ts`, beside `DOCUMENT_TYPES`:

```ts
  DOCUMENT_CHECKLIST: '/document-checklist',
```

- [ ] **Step 2: Add the controller**

In `backend/src/modules/masters/masters.controller.ts`, beside `registrationOptions`:

```ts
/**
 * The KYC checklist the public registration form renders (C-01).
 *
 * Anonymous, because the form is filled in before an account exists. The payload
 * is only what the form prints on screen — no ids, no counts, nothing about any
 * applicant.
 */
export const publicDocumentChecklist = handler(async (_req, res) => {
  const items = await checklistFor('APPLICATION');

  handleApiResponse(res, {
    responseType: RES_STATUS.READ,
    data: serialise({
      items: items.map(({ id, ...rest }) => {
        void id;

        return rest;
      }),
    }),
  });
});
```

Add `import { checklistFor } from '@modules/masters/masters.checklist';` to the
controller's imports, and match the exact `handleApiResponse` / `serialise` call
style of the `registrationOptions` handler directly above it.

- [ ] **Step 3: Mount the route**

In `masters.routes.ts`, on the public router beside the other public reads:

```ts
mastersPublicRouter.get(END_POINTS.DOCUMENT_CHECKLIST, controller.publicDocumentChecklist);
```

- [ ] **Step 4: Verify by hand**

```bash
cd backend && npm run dev
# in another shell:
curl -s http://localhost:4000/api/v1/public/document-checklist | head -c 400
```

Expected: the three seeded types, `is_required: true`, `sides: "SINGLE"`, and
**no `id` field**.

- [ ] **Step 5: Checkpoint**

Run: `cd backend && npm run typecheck && npm run lint`
*(git: `git commit -am "feat(masters): public document checklist endpoint"`)*

---

### Task 8: Registration accepts a dynamic set of files

`POST /auth/register` is one multipart request whose multer field names are fixed
at route-definition time (`auth.routes.ts:20`). Dynamic types have no fixed names.

**Files:**
- Modify: `backend/src/modules/auth/register.constants.ts` (delete both constants, add the field-name codec)
- Modify: `backend/src/modules/auth/auth.routes.ts:19-65`
- Modify: `backend/src/modules/auth/auth.controller.ts:84-100`
- Modify: `backend/src/modules/auth/register.service.ts:85-97`
- Create: `backend/src/modules/auth/register.fields.test.ts`

**Interfaces:**
- Consumes: `checklistFor` (Task 4); `requiredSides`, `missingSides`, `describeSide` (Task 1)
- Produces:
  - `uploadFieldName(code: string, side: DocumentSideValue): string` → `document__AADHAAR_CARD__BACK`
  - `parseUploadFieldName(field: string): { code: string; side: DocumentSideValue } | null`
  - `registrationUpload: RequestHandler` — middleware that builds multer's field list from the live checklist

`multer.any()` is **not** acceptable here: it accepts any field name at all, on a
public unauthenticated endpoint. The whitelist stays; it is just computed instead
of literal.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/auth/register.fields.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { parseUploadFieldName, uploadFieldName } from '@modules/auth/register.constants';

describe('uploadFieldName', () => {
  it('names a single-sided upload', () => {
    expect(uploadFieldName('PAN_DOCUMENT', 'SINGLE')).toBe('document__PAN_DOCUMENT__SINGLE');
  });

  it('names each face of a two-sided upload distinctly', () => {
    expect(uploadFieldName('AADHAAR_CARD', 'FRONT')).toBe('document__AADHAAR_CARD__FRONT');
    expect(uploadFieldName('AADHAAR_CARD', 'BACK')).toBe('document__AADHAAR_CARD__BACK');
  });
});

describe('parseUploadFieldName', () => {
  it('round-trips', () => {
    expect(parseUploadFieldName(uploadFieldName('AADHAAR_CARD', 'BACK'))).toEqual({
      code: 'AADHAAR_CARD',
      side: 'BACK',
    });
  });

  it('rejects a field that is not one of ours', () => {
    expect(parseUploadFieldName('avatar')).toBeNull();
  });

  it('rejects an unknown face', () => {
    expect(parseUploadFieldName('document__PAN_DOCUMENT__SIDEWAYS')).toBeNull();
  });

  it('rejects a code that is not a legal document code', () => {
    expect(parseUploadFieldName('document__../../etc/passwd__FRONT')).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && npm test -- register.fields`
Expected: FAIL — neither function exists.

- [ ] **Step 3: Replace the constants**

Replace the whole of `backend/src/modules/auth/register.constants.ts`:

```ts
import type { DocumentSideValue } from '@modules/document/document.sides';

/**
 * Multipart field names on `POST /auth/register`.
 *
 * The three registration documents used to be a fixed list with three fixed field
 * names. The association configures its own checklist now (M5), so the names are
 * derived from the type's code and the face instead: `document__AADHAAR_CARD__BACK`.
 *
 * The code is re-validated on parse against the same pattern screen A-12 enforces.
 * `multer.any()` would have removed the need for this codec and is deliberately not
 * used — `/auth/register` is public and unauthenticated, and an open field
 * whitelist there is a hole, not a convenience.
 */

const PREFIX = 'document';
const SEPARATOR = '__';
const CODE_PATTERN = /^[A-Z][A-Z0-9_]*$/;
const SIDES: readonly DocumentSideValue[] = ['SINGLE', 'FRONT', 'BACK', 'COMBINED'];

export const uploadFieldName = (code: string, side: DocumentSideValue): string =>
  [PREFIX, code, side].join(SEPARATOR);

export const parseUploadFieldName = (
  field: string,
): { code: string; side: DocumentSideValue } | null => {
  const parts = field.split(SEPARATOR);
  if (parts.length !== 3) return null;

  const [prefix, code, side] = parts as [string, string, string];
  if (prefix !== PREFIX) return null;
  if (!CODE_PATTERN.test(code)) return null;
  if (!SIDES.includes(side as DocumentSideValue)) return null;

  return { code, side: side as DocumentSideValue };
};
```

Note the separator is `__`, so a code containing a single underscore
(`GST_CERTIFICATE`) still splits into exactly three parts.

- [ ] **Step 4: Build multer's field list per request**

In `backend/src/modules/auth/auth.routes.ts`, replace lines 19-22 and the
`registrationUpload.fields(...)` call at line 58:

```ts
import { checklistFor } from '@modules/masters/masters.checklist';
import { requiredSides } from '@modules/document/document.sides';
import { parseUploadFieldName, uploadFieldName } from '@modules/auth/register.constants';

const upload = multer({
  storage: multer.memoryStorage(),
  // Per-file ceiling only. The real limit is the document type's own max_size_mb,
  // checked against the bytes in document.service; this is the backstop that stops
  // a 2GB body being buffered before we get that far.
  limits: { fileSize: 50 * 1024 * 1024 },
});

/**
 * Accept exactly the files the live checklist asks for.
 *
 * Built per request because an admin can add a document type at any moment and
 * the next applicant must be able to send it. Still a whitelist: a field name the
 * checklist does not name is rejected by multer, on a public endpoint where that
 * matters.
 */
const registrationUpload: RequestHandler = (req, res, next) => {
  void checklistFor('APPLICATION')
    .then((items) => {
      const fields = items.flatMap((item) =>
        requiredSides(item.sides).map((side) => ({
          name: uploadFieldName(item.code, side),
          maxCount: 1,
        })),
      );

      upload.fields(fields)(req, res, next);
    })
    .catch(next);
};
```

Import `RequestHandler` from `express`.

- [ ] **Step 5: Read the files back generically**

In `auth.controller.ts`, replace the `REGISTRATION_KYC_CODES.flatMap(...)` block
(lines 86-100):

```ts
  const uploads = req.files as Record<string, Express.Multer.File[]> | undefined;

  const files = Object.entries(uploads ?? {}).flatMap(([field, list]) => {
    const parsed = parseUploadFieldName(field);
    const file = list?.[0];
    if (!parsed || !file) return [];

    return [
      {
        code: parsed.code,
        side: parsed.side,
        originalName: file.originalname,
        buffer: file.buffer,
        declaredMime: file.mimetype,
      },
    ];
  });
```

Update the `RegistrationFile` type in `register.service.ts` to carry
`code: string` and `side: DocumentSideValue` (it was `RegistrationKycCode`).

- [ ] **Step 6: Require what the checklist requires**

Replace `register.service.ts` lines 85-97:

```ts
  /*
    Every required face must be here.

    Read from the master, not from a constant: an admin who adds a required
    document type is asking for it from the next applicant onward, and an admin
    who marks one optional has stopped requiring it. Optional types are accepted
    if supplied and never demanded.
  */
  const checklist = await checklistFor('APPLICATION');

  for (const type of checklist.filter((item) => item.is_required)) {
    const supplied = files
      .filter((file) => file.code === type.code)
      .map((file) => sideForUpload(type.sides, file.side, file.declaredMime));

    for (const side of missingSides(type.sides, supplied)) {
      throw new AppError({
        errorType: ERROR_TYPES.VALIDATION_ERROR,
        messageKey: 'document.fileRequired',
        replacements: { documentType: describeSide(type.name, side) },
        details: { document: uploadFieldName(type.code, side) },
      });
    }
  }

  for (const file of files) {
    await documentService.validateApplicationFileBuffer(
      file.code,
      file.buffer,
      file.declaredMime,
      file.side,
    );
  }
```

Then in the storage loop further down, pass `requestedSide: file.side` to
`storeApplicationFile`.

- [ ] **Step 7: Check the message key takes the replacement**

`backend/src/locales/en.json` line 209 already reads
`"required": "{{documentType}} is required"`. Confirm `document.fileRequired`
resolves to it; if `fileRequired` is a separate key with no placeholder, give it
one: `"fileRequired": "{{documentType}} is required"`.

- [ ] **Step 8: Run to verify it passes**

Run: `cd backend && npm test`
Expected: PASS, all suites including 5 new field-name tests.

- [ ] **Step 9: Checkpoint**

Run: `cd backend && npm run typecheck && npm run lint`
Expected: **baseline 4 errors only.** The backend is now fully migrated; if
anything still references `RegistrationDocumentType` or `REGISTRATION_KYC_CODES`,
fix it before moving to the frontends.

Run: `cd backend && grep -rn "REGISTRATION_KYC_CODES\|RegistrationDocumentType\|REGISTRATION_DOCUMENT_RULES" src` — expected: no results.
*(git: `git commit -am "feat(auth): registration accepts the configured checklist"`)*

---

### Task 9: The API tells clients the type name and the face

Both frontends currently translate a code into a label themselves. They stop.

**Files:**
- Modify: `backend/src/modules/application/application.service.ts` (application detail serialiser)
- Modify: `backend/src/modules/member/member.service.ts` or wherever `MemberDocument` is serialised

**Interfaces:**
- Consumes: Task 6's `listApplicationDocuments` include
- Produces: every serialised application/member document carries
  `document_type: { code: string; name: string; sides: 'SINGLE' | 'FRONT_AND_BACK' }` and `side: DocumentSideValue`.
  The old scalar `document_type: "GST_CERTIFICATE"` is **gone**.

- [ ] **Step 1: Find every serialiser**

Run: `cd backend && grep -rn "document_type" src/modules/application src/modules/member --include=*.ts`

- [ ] **Step 2: Shape each one**

For each place a document is put into a response, emit:

```ts
{
  id: doc.id,
  document_type: {
    code: doc.document_type.code,
    name: doc.document_type.name,
    sides: doc.document_type.sides,
  },
  side: doc.side,
  original_name: doc.original_name,
  // ...the fields it already emitted
}
```

`MemberDocumentsPanel` already reads `document.document_type.name`, so the member
side may already be correct — verify rather than assume.

- [ ] **Step 3: Verify by hand**

Start the backend, register an applicant through the customer app (or re-use an
existing application id), and:

```bash
curl -s -H "Authorization: Bearer <token>" \
  http://localhost:4000/api/v1/applications/<id> | python3 -m json.tool | grep -A 6 document_type
```

Expected: an object with `code`, `name` and `sides`, plus a sibling `side`.

- [ ] **Step 4: Checkpoint**

Run: `cd backend && npm run typecheck && npm run lint && npm test`
*(git: `git commit -am "feat(api): documents carry their type name and face"`)*

---

### Task 10: Admin — the Sides field on screen A-12

**Invoke the `association-admin-ui` skill before starting.** `Categories.tsx` is
the reference implementation for this screen's shape.

**Files:**
- Modify: `admin/src/services/mastersService.ts:74-88` (`DocumentType` interface)
- Modify: `admin/src/pages/masters/DocumentTypes.tsx` (options constant, drawer field, table column, filter)
- Modify: `backend/src/modules/masters/masters.types.ts:230-253` (accept `sides` on create/update, filter on list)

**Interfaces:**
- Consumes: the `sides` column from Task 3
- Produces: admins can set Front only / Front and back; the value round-trips through create, edit and list.

- [ ] **Step 1: Accept `sides` on the API**

In `backend/src/modules/masters/masters.types.ts`, add to
`createDocumentTypeSchema` after `is_required`:

```ts
  sides: z.nativeEnum(DocumentSides).default(DocumentSides.SINGLE),
```

Import `DocumentSides` from `@prisma/client` alongside `DocumentAppliesTo`.
`updateDocumentTypeSchema` picks it up automatically (it is
`createDocumentTypeSchema.omit({ code: true }).partial()`).

Add to `documentTypeListQuerySchema`:

```ts
  sides: enumCsv(Object.values(DocumentSides)),
```

and thread `sides` through `listDocumentTypes` in the service and the repository
exactly as `applies_to` is threaded today.

- [ ] **Step 2: Add the field to the admin type**

In `admin/src/services/mastersService.ts`, add to `DocumentType` after
`is_required`:

```ts
  sides: DocumentSides;
```

and export the union beside `DocumentAppliesTo`:

```ts
export type DocumentSides = 'SINGLE' | 'FRONT_AND_BACK';
```

- [ ] **Step 3: Add the options constant**

In `admin/src/pages/masters/DocumentTypes.tsx`, beside `APPLIES_TO` (line 64):

```tsx
const SIDES: { value: DocumentSides; label: string; hint: string }[] = [
  {
    value: 'SINGLE',
    label: 'Front only',
    hint: 'One file is the whole document — a certificate or a statement.',
  },
  {
    value: 'FRONT_AND_BACK',
    label: 'Front and back',
    hint: 'An ID card whose reverse carries the address or signature. Both are asked for.',
  },
];
```

Import `type DocumentSides` from `@/services/mastersService`.

- [ ] **Step 4: Add the drawer field**

The drawer currently pairs *Asked for* with *Maximum size (MB)* in a
`grid grid-cols-2 gap-4`, then *File types* with *Display order*. Insert a new
pair row directly after the *Asked for* row so the two questions about **what
this document is** sit together, above the two about **what file is acceptable**:

```tsx
          <div className="grid grid-cols-2 gap-4">
            <Form.Item
              name="sides"
              label={
                <FieldLabel
                  label="Sides"
                  help="Front and back asks the member for two files. One multi-page PDF counts as both."
                />
              }
              className="min-w-0"
            >
              <FormSelect options={SIDES} searchThreshold={6} />
            </Form.Item>

            <div />
          </div>
```

The empty `<div />` keeps the field at half width, matching every other short
control on this drawer rather than stretching one select across the row.

- [ ] **Step 5: Default it on open**

Wherever the drawer's `form.setFieldsValue` runs for a create (search
`setFieldsValue` in this file), add `sides: 'SINGLE'`. On an edit, add
`sides: editing.sides`.

- [ ] **Step 6: Add the table column**

Beside the existing `Required` / `Offered` columns, using `Badge` (not a
hand-rolled pill):

```tsx
                  {
                    title: 'Sides',
                    dataIndex: 'sides',
                    width: 130,
                    render: (value: DocumentSides) => (
                      <Badge>{value === 'FRONT_AND_BACK' ? 'Front + back' : 'Front only'}</Badge>
                    ),
                  },
```

Import `Badge` from `@/components/ui` if it is not already imported.

- [ ] **Step 7: Verify in the browser**

```bash
cd backend && npm run dev    # shell 1
cd admin && npm run dev      # shell 2
```

Open `http://localhost:3001/masters/document-types`:
- Add a type with Sides = Front and back → the table shows `Front + back`.
- Edit it back to Front only → saves and the column updates.
- Reload → the value persisted.

- [ ] **Step 8: Checkpoint**

Run: `cd admin && npx tsc -p tsconfig.app.json --noEmit`
Expected: the 4 baseline unused-variable errors in `Categories.tsx` / `Fees.tsx`, nothing new.
Run: `cd backend && npm run typecheck && npm run lint`
*(git: `git commit -am "feat(admin): sides on the document types master"`)*

---

### Task 11: Admin — review panels show the real name and each face

**Invoke the `association-admin-ui` skill before starting.**

**Files:**
- Modify: `admin/src/services/applicationsService.ts:166-190` (delete `RegistrationDocumentType` and `REGISTRATION_DOCUMENT_LABELS`; reshape `ApplicationDocument`)
- Modify: `admin/src/pages/applications/DocumentsPanel.tsx:119-260`
- Modify: `admin/src/pages/members/MemberDocumentsPanel.tsx:120-270`

**Interfaces:**
- Consumes: Task 9's response shape
- Produces: nothing downstream

- [ ] **Step 1: Reshape the service types**

In `admin/src/services/applicationsService.ts`, delete lines 166-172
(`RegistrationDocumentType` and `REGISTRATION_DOCUMENT_LABELS`) and change the
document's field (line 187):

```ts
export type DocumentSide = 'SINGLE' | 'FRONT' | 'BACK' | 'COMBINED';

export const DOCUMENT_SIDE_LABELS: Record<DocumentSide, string> = {
  SINGLE: '',
  FRONT: 'Front',
  BACK: 'Back',
  COMBINED: 'Both sides',
};

// ...inside the document interface:
  document_type: { code: string; name: string; sides: 'SINGLE' | 'FRONT_AND_BACK' };
  side: DocumentSide;
```

- [ ] **Step 2: Replace every label lookup**

In `DocumentsPanel.tsx`, the five uses of
`REGISTRATION_DOCUMENT_LABELS[target.document.document_type]` (lines 119, 120,
157, 251, 252) all become a single helper defined at the top of the file:

```tsx
/** "Aadhaar Card — Back", or just "PAN Document" when there is only one file. */
const documentLabel = (document: ApplicationDocument) =>
  DOCUMENT_SIDE_LABELS[document.side]
    ? `${document.document_type.name} — ${DOCUMENT_SIDE_LABELS[document.side]}`
    : document.document_type.name;
```

Then `documentLabel(target.document)` at each of the five sites. The confirm-dialog
copy is unchanged apart from the name it interpolates.

- [ ] **Step 3: Show the face in the row**

At line 157, where the name is rendered, render `documentLabel(document)`. Where
the row already shows a `Badge` for Required/Optional, leave it — the face is part
of the name, not a second badge, because "Aadhaar Card" appearing twice in a list
with no distinguishing text is the actual problem being solved.

- [ ] **Step 4: Same treatment on the member panel**

`MemberDocumentsPanel.tsx` already reads `document.document_type.name` at lines
122, 123, 173, 265, 266. Wrap each in the same `documentLabel` helper (defined
locally in that file — two small helpers beat one shared import for two files
that will diverge).

- [ ] **Step 5: Verify in the browser**

With a two-sided type configured and an application that has both faces uploaded:
- The review panel lists two rows under that document, labelled Front and Back.
- Rejecting the back leaves the front's verified state untouched.
- The confirm dialog names the face: *"Reject Aadhaar Card — Back?"*

- [ ] **Step 6: Checkpoint**

Run: `cd admin && npx tsc -p tsconfig.app.json --noEmit`
Run: `cd admin && grep -rn "REGISTRATION_DOCUMENT_LABELS" src` — expected: no results.
*(git: `git commit -am "feat(admin): per-face document review"`)*

---

### Task 12: Customer — the registration form renders the live checklist

**Files:**
- Modify: `customer/src/components/auth/RegistrationForm.tsx:43-45, 406-408, 601-603`
- Create: `customer/src/services/PublicChecklistService.ts` (or add to the existing public service — follow the file that already calls `/public/registration-options`)

**Interfaces:**
- Consumes: `GET /api/v1/public/document-checklist` (Task 7); the field-name convention from Task 8
- Produces: nothing downstream

- [ ] **Step 1: Fetch the checklist**

Add a fetch of `/public/document-checklist` beside whatever already loads
`/public/registration-options` in this form, into state:

```ts
interface ChecklistItem {
  code: string;
  name: string;
  description: string | null;
  is_required: boolean;
  sides: 'SINGLE' | 'FRONT_AND_BACK';
  max_size_mb: number;
  allowed_mime: string[];
  display_order: number;
}
```

- [ ] **Step 2: Replace the hardcoded list**

Delete lines 43-45 (`{ key: 'gst_certificate', ... }` and its two siblings).
Derive the upload slots instead:

```tsx
const slots = checklist.flatMap((item) =>
  (item.sides === 'FRONT_AND_BACK' ? (['FRONT', 'BACK'] as const) : (['SINGLE'] as const)).map(
    (side) => ({
      field: `document__${item.code}__${side}`,
      label: side === 'SINGLE' ? item.name : `${item.name} — ${side === 'FRONT' ? 'front' : 'back'}`,
      description: item.description,
      required: item.is_required,
      maxSizeMb: item.max_size_mb,
      accept: item.allowed_mime.join(','),
    }),
  ),
);
```

Render one upload control per slot, in `display_order`. The state at line 406
becomes a `Record<string, UploadFile[]>` keyed by `slot.field` and initialised
from `slots`.

- [ ] **Step 3: Build the request generically**

Replace lines 601-603:

```ts
        for (const slot of slots) {
          const file = kycFiles[slot.field]?.[0]?.originFileObj as File | undefined;
          if (file) formData.append(slot.field, file);
        }
```

Match how the surrounding code builds its `FormData` — if it currently hands an
object to a service that constructs the body, change that service instead and
keep the component's shape.

- [ ] **Step 4: Client-side validation mirrors the server**

Before submit, block with a message naming the slot when
`slot.required && !kycFiles[slot.field]?.length`. The server enforces it too
(Task 8 Step 6); this is only so the applicant is not told after a round trip.

- [ ] **Step 5: Verify in the browser**

```bash
cd backend && npm run dev     # shell 1
cd customer && npm run dev    # shell 2
```

- Register with the three seeded types → three upload boxes, submit succeeds.
- In the admin, add a required two-sided type → reload registration → **five**
  boxes, and submitting without the back is refused naming the back.
- In the admin, mark a type optional → reload → it is still shown, and submitting
  without it succeeds.

- [ ] **Step 6: Checkpoint**

Run: `cd customer && npx tsc --noEmit`
Run: `cd customer && grep -rn "gst_certificate\|trade_licence" src` — expected: no results.
*(git: `git commit -am "feat(customer): registration renders the configured checklist"`)*

---

### Task 13: Customer — application step, resubmit and types

**Files:**
- Modify: `customer/src/types/application.ts:82, 181, 311, 322-340`
- Modify: `customer/src/types/resubmit.ts:29`
- Modify: `customer/src/components/application/DocumentsStep.tsx:102-133, 300-310`

**Interfaces:**
- Consumes: Task 6's `missingDocuments` shape, Task 9's document shape
- Produces: nothing downstream

- [ ] **Step 1: Retype the document**

In `customer/src/types/application.ts`, delete `RegistrationDocumentType`
(line 82) and `REGISTRATION_DOCUMENT_TYPES` (line 311). `ApplicationDocument`
gains:

```ts
  document_type: { code: string; name: string; sides: 'SINGLE' | 'FRONT_AND_BACK' };
  side: 'SINGLE' | 'FRONT' | 'BACK' | 'COMBINED';
```

Update `normaliseApplicationDocument` (line 322) to read the nested object, and
to fall back to `{ code: '', name: 'Document', sides: 'SINGLE' }` when the field
is absent, matching how the rest of that file degrades.

`Completeness.missingDocuments` becomes
`Array<{ code: string; name: string; side: string; label: string }>`.

- [ ] **Step 2: Delete the resubmit triple**

`customer/src/types/resubmit.ts:29` — delete `RESUBMIT_DOCUMENT_TYPES` and
whatever validates against it. The resubmit page already works from
`requires_reupload` per file, which is per-face once the backend records the face;
it needs the label, not the list.

- [ ] **Step 3: Render sides in the documents step**

`DocumentsStep.tsx` builds `rows` (line 102) by keying on `document.document_type`
as a string. Key on `` `${code}:${side}` `` instead, and build the row set from the
checklist's `(type, side)` pairs rather than from `sort()`ed codes:

```tsx
    const slots = (checklist?.items ?? []).flatMap((item) =>
      (item.sides === 'FRONT_AND_BACK' ? (['FRONT', 'BACK'] as const) : (['SINGLE'] as const)).map(
        (side) => ({ item, side, key: `${item.code}:${side}` }),
      ),
    );
```

The row's display name uses the same "— front" / "— back" suffix as Task 12, so
the applicant sees the same words in both places.

- [ ] **Step 4: Point the step at the right checklist**

`DocumentsStep` currently calls `useDocumentChecklist()`, which fetches
`GET /members/me/documents` — the **member profile** checklist, not the
application one. That is wrong now that the two surfaces differ. Point it at the
public application checklist from Task 7 instead, and leave
`useDocumentChecklist` for the member profile screens that legitimately use it.

- [ ] **Step 5: Show the missing-document labels verbatim**

Wherever `completeness.missingDocuments` is rendered, print `item.label` — the
backend already composed "Aadhaar Card (back)". Do not rebuild the string
client-side.

- [ ] **Step 6: Verify in the browser**

- Open a returned application with a rejected back → only the back is asked for.
- Upload it → the step reports complete and submit is allowed.
- The blocking message names the face, not a code.

- [ ] **Step 7: Checkpoint**

Run: `cd customer && npx tsc --noEmit`
Run: `cd customer && grep -rn "GST_CERTIFICATE\|PAN_DOCUMENT\|TRADE_LICENCE" src` — expected: no results.
*(git: `git commit -am "feat(customer): per-face document step and resubmit"`)*

---

### Task 14: Regression pass

**Files:**
- Modify: `sarvadhi-sentinel/config.js` and `run.js` (extend the `masters` and `application` suites)

**Interfaces:**
- Consumes: everything above
- Produces: a repeatable gate

Per `CLAUDE.md` and `testing-strategy.md` §1, **the existing Self-Test Agent in
`sarvadhi-sentinel/` is the only testing agent — do not create another.**

- [ ] **Step 1: Extend the `masters` suite**

Add two cases, matching the file's existing case style:
- Deleting a document type that has an uploaded file → **409**, not 500 and not
  200. This is the guard from Task 2 and the reason the FK can exist.
- Creating a type with `sides: 'FRONT_AND_BACK'` round-trips through list and
  detail.

- [ ] **Step 2: Extend the `application` suite**

One end-to-end case:
1. Admin creates a required two-sided document type.
2. `GET /public/document-checklist` includes it with `sides: 'FRONT_AND_BACK'`.
3. Register with only the front → **422**, message names the back.
4. Register with both → 201.
5. Admin rejects the back only → the front stays `VERIFIED`.
6. Approve before the back is replaced → **409**.
7. Applicant replaces the back → approve → 200.
8. Admin deletes the throwaway type → **409** (in use), then deactivates it
   instead → 200.

- [ ] **Step 3: Run the whole gate**

```bash
cd backend && npm test && npm run typecheck && npm run lint && npm run prisma:status && npm run db:check-comments
cd admin && npx tsc -p tsconfig.app.json --noEmit
cd customer && npx tsc --noEmit
cd sarvadhi-sentinel && npm start
```

Expected: tests pass; typecheck shows **only** the documented baseline errors;
`prisma migrate status` clean; `db:check-comments` zero rows; Sentinel green.

- [ ] **Step 4: Manual UX pass**

Walk both journeys against the four-line rubric in `ux-principles.md` §2 —
Current State → Required Action → Next Step → Expected Result — for the
registration documents step and the admin review panel. A screen that has to
narrate the answers fails.

- [ ] **Step 5: Final checkpoint**
*(git: `git commit -am "test: sentinel coverage for dynamic document types and sides"`)*

---

## Rollback

The migration is not reversible by `prisma migrate resolve` — it drops a column.
To roll back: restore the database from the pre-deploy backup
(`backup-recovery.md`) and redeploy the previous build. Do not attempt to
re-create `RegistrationDocumentType` by hand on a database that has already
accepted uploads against admin-created types; those rows have no enum value to
map to.

Because of that, Task 3 Step 7 is rehearsed against a restored copy **before** it
runs anywhere real.
