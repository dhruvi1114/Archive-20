# Company Team Logins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one member company have several people who each log in with their own account, so the event module can pick attendees from a real team roster.

**Architecture:** A join table `MemberUsers` replaces `Members.primary_user_id` as the way a login resolves to a company; the primary user becomes an `OWNER` row and the column stays only as a pointer. Invites reuse the existing `issueInitialPasswordLink` / `setInitialPassword` pair from `auth.service.ts` — no new token type, no new password path. Everything member-facing hangs off `/members/me/team`.

**Tech Stack:** Node.js + Express + TypeScript, Prisma, PostgreSQL, Vitest, Next.js (customer app).

**Spec:** `docs/superpowers/specs/2026-08-26-event-module-schema.md` (section 1 and section 0) and `docs/superpowers/specs/2026-08-26-event-module-design.md` (section 2).

**Migration owner:** Agent B. Agent A does not touch `prisma/` during this cycle (migration-strategy.md rule 5).

## Global Constraints

Copied verbatim from spec section 0. Every task below implicitly includes these.

- **Integer enums.** Every enum on a table created here is `Int @db.SmallInt` with a documented code map — never a Prisma `enum`, never a Postgres native enum. Codes start at 0, are append-only, and are never reused. Existing M0–M5 tables keep their string enums.
- **`bigint` primary keys** on every table. No `uuid` columns anywhere.
- **FK actions:** `CASCADE` for owned children, `SET NULL` for pointers, `NO ACTION` everywhere else (`onDelete: NoAction` in Prisma).
- **Every migration is wrapped in an explicit transaction** — `migration.sql` opens with `BEGIN;` and ends with `COMMIT;`.
- **Every new table and every new column gets a `COMMENT ON`.** `npm run db:check-comments` must return zero rows.
- **Audit block on every new table:** `createdAt`, `created_by_user_id`, `created_by_admin_id`, `updatedAt`, `updated_by_user_id`, `updated_by_admin_id` (+ `deletedAt` where soft-deleted). Both actor columns null means the system did it.
- **Naming (ADR-003):** table `PascalCasePlural`, column `snake_case`, audit timestamps camelCase, via `@@map` / `@map`.
- Raw SQL double-quotes identifiers: `FROM "MemberUsers"`.

---

### Task 1: `MemberUsers` and `MemberTeamInvites` tables

**Files:**
- Modify: `backend/prisma/schema/member.prisma` (append at end of file)
- Create: `backend/prisma/migrations/<timestamp>_m7_add_member_team_logins/migration.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: Prisma models `MemberUser` (mapped `MemberUsers`) and `MemberTeamInvite` (mapped `MemberTeamInvites`); code maps `MEMBER_ROLE` and `MEMBER_USER_STATUS` are added in Task 2.

- [ ] **Step 1: Add the two models to `member.prisma`**

Append to `backend/prisma/schema/member.prisma`:

```prisma
/// One login belonging to one member company. Replaces `Members.primary_user_id`
/// as the way a signed-in user resolves to a company: the primary user is simply
/// the row here whose `member_role` is 0 (OWNER). The column stays on `Members`
/// as a pointer so existing code and the approval flow keep working.
model MemberUser {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// FK to Members.id. ON DELETE CASCADE — a team row is meaningless without its firm.
  member_id BigInt

  /// FK to Users.id. ON DELETE NO ACTION — a login is never deleted out from under a team row.
  user_id BigInt

  /// 0 = OWNER (the company's primary login, exactly one per member),
  /// 1 = TEAM. Finer permissions are deliberately deferred.
  member_role Int @default(1) @db.SmallInt

  /// 0 = INVITED (email sent, password not set), 1 = ACTIVE, 2 = DEACTIVATED.
  status Int @default(0) @db.SmallInt

  /// Which member login sent the invite. Null for the OWNER row created at approval.
  invited_by_user_id BigInt?

  /// When the invitee set their password and the row went ACTIVE.
  accepted_at DateTime? @db.Timestamptz(6)

  /// When an owner switched this person off. Kept for history rather than deleted.
  deactivated_at DateTime? @db.Timestamptz(6)

  /// Row created at.
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// Member login that created this row, when a member did.
  created_by_user_id BigInt?

  /// Staff account that created this row, when staff did.
  created_by_admin_id BigInt?

  /// Row last changed at.
  updatedAt DateTime @updatedAt @db.Timestamptz(6)

  /// Member login that last changed this row.
  updated_by_user_id BigInt?

  /// Staff account that last changed this row.
  updated_by_admin_id BigInt?

  /// The firm this login belongs to.
  member Member @relation(fields: [member_id], references: [id], onDelete: Cascade, onUpdate: Cascade)

  /// The login itself.
  user User @relation("MemberUserLogin", fields: [user_id], references: [id], onDelete: NoAction, onUpdate: Cascade)

  @@unique([member_id, user_id])
  @@index([member_id, status])
  @@map("MemberUsers")
}

/// An outstanding invitation to join a company's team. The token is the same
/// opaque password-reset token the approval email already uses, so acceptance
/// runs through `setInitialPassword` and no second password path exists.
model MemberTeamInvite {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// FK to Members.id. ON DELETE CASCADE — owned by the firm.
  member_id BigInt

  /// FK to Users.id — the login created for the invitee. ON DELETE NO ACTION.
  user_id BigInt

  /// Address the invite was sent to, as typed by the owner.
  email String @db.Citext

  /// Name as typed by the owner; copied onto Users.full_name.
  full_name String @db.VarChar(150)

  /// Job title shown on the team screen and pre-filled into event attendee rows.
  designation String? @db.VarChar(100)

  /// Which member login sent it.
  invited_by_user_id BigInt

  /// When the invite stops being usable. Mirrors the password-reset token expiry.
  expires_at DateTime @db.Timestamptz(6)

  /// Set when the invitee sets their password.
  accepted_at DateTime? @db.Timestamptz(6)

  /// Set when the owner cancels the invite before it is accepted.
  revoked_at DateTime? @db.Timestamptz(6)

  /// Row created at.
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// Member login that created this row.
  created_by_user_id BigInt?

  /// Staff account that created this row.
  created_by_admin_id BigInt?

  /// Row last changed at.
  updatedAt DateTime @updatedAt @db.Timestamptz(6)

  /// Member login that last changed this row.
  updated_by_user_id BigInt?

  /// Staff account that last changed this row.
  updated_by_admin_id BigInt?

  /// The firm inviting.
  member Member @relation(fields: [member_id], references: [id], onDelete: Cascade, onUpdate: Cascade)

  @@index([member_id, createdAt(sort: Desc)])
  @@map("MemberTeamInvites")
}
```

Add the back-relations. In `model Member`, add:

```prisma
  /// Every login that belongs to this firm.
  team_users MemberUser[]

  /// Invitations this firm has sent.
  team_invites MemberTeamInvite[]
```

In `model User` (in `identity.prisma`), add:

```prisma
  /// The company team row that ties this login to a member, if any.
  member_user MemberUser[] @relation("MemberUserLogin")
```

- [ ] **Step 2: Generate the migration SQL without applying it**

Run:
```bash
cd backend && npx prisma migrate dev --create-only --name m7_add_member_team_logins
```
Expected: a new folder under `prisma/migrations/` containing `migration.sql`. Do **not** let it apply.

- [ ] **Step 3: Wrap the migration, add the partial indexes, the backfill and every comment**

Edit the generated `migration.sql` so the whole file reads as one transaction. Put `BEGIN;` on the first line, then the Prisma-generated `CREATE TABLE` statements, then append the block below before a final `COMMIT;`:

```sql
-- Exactly one OWNER per member. A partial unique index, not a plain one,
-- because TEAM rows are unrestricted.
CREATE UNIQUE INDEX "MemberUsers_one_owner_per_member"
  ON "MemberUsers" ("member_id")
  WHERE "member_role" = 0;

-- At most one open invite per address per firm. Accepted and revoked invites
-- stay as history and must not block a re-invite.
CREATE UNIQUE INDEX "MemberTeamInvites_one_open_per_email"
  ON "MemberTeamInvites" ("member_id", "email")
  WHERE "accepted_at" IS NULL AND "revoked_at" IS NULL;

-- At most one actor per event.
ALTER TABLE "MemberUsers" ADD CONSTRAINT "MemberUsers_created_by_one_actor"
  CHECK (NOT ("created_by_user_id" IS NOT NULL AND "created_by_admin_id" IS NOT NULL));
ALTER TABLE "MemberUsers" ADD CONSTRAINT "MemberUsers_updated_by_one_actor"
  CHECK (NOT ("updated_by_user_id" IS NOT NULL AND "updated_by_admin_id" IS NOT NULL));
ALTER TABLE "MemberTeamInvites" ADD CONSTRAINT "MemberTeamInvites_created_by_one_actor"
  CHECK (NOT ("created_by_user_id" IS NOT NULL AND "created_by_admin_id" IS NOT NULL));
ALTER TABLE "MemberTeamInvites" ADD CONSTRAINT "MemberTeamInvites_updated_by_one_actor"
  CHECK (NOT ("updated_by_user_id" IS NOT NULL AND "updated_by_admin_id" IS NOT NULL));

-- Enum codes are only meaningful if they are in range.
ALTER TABLE "MemberUsers" ADD CONSTRAINT "MemberUsers_member_role_range"
  CHECK ("member_role" IN (0, 1));
ALTER TABLE "MemberUsers" ADD CONSTRAINT "MemberUsers_status_range"
  CHECK ("status" IN (0, 1, 2));

-- Backfill: every existing member's primary login becomes its OWNER row.
-- Status 1 (ACTIVE) because these logins already have passwords.
-- Both actor columns null: this row was made by a migration, not a person.
INSERT INTO "MemberUsers" (
  "member_id", "user_id", "member_role", "status", "accepted_at", "createdAt", "updatedAt"
)
SELECT m."id", m."primary_user_id", 0, 1, now(), now(), now()
FROM "Members" m
WHERE m."primary_user_id" IS NOT NULL
  AND m."deletedAt" IS NULL;

COMMENT ON TABLE "MemberUsers" IS 'One login belonging to one member company; the OWNER row replaces Members.primary_user_id as the resolution path.';
COMMENT ON COLUMN "MemberUsers"."id" IS 'Surrogate key.';
COMMENT ON COLUMN "MemberUsers"."member_id" IS 'FK to Members.id. ON DELETE CASCADE.';
COMMENT ON COLUMN "MemberUsers"."user_id" IS 'FK to Users.id. ON DELETE NO ACTION.';
COMMENT ON COLUMN "MemberUsers"."member_role" IS '0 = OWNER (exactly one per member), 1 = TEAM.';
COMMENT ON COLUMN "MemberUsers"."status" IS '0 = INVITED, 1 = ACTIVE, 2 = DEACTIVATED.';
COMMENT ON COLUMN "MemberUsers"."invited_by_user_id" IS 'Member login that sent the invite; null for the OWNER row.';
COMMENT ON COLUMN "MemberUsers"."accepted_at" IS 'When the invitee set their password and the row went ACTIVE.';
COMMENT ON COLUMN "MemberUsers"."deactivated_at" IS 'When an owner switched this person off.';
COMMENT ON COLUMN "MemberUsers"."createdAt" IS 'Row created at.';
COMMENT ON COLUMN "MemberUsers"."created_by_user_id" IS 'Member login that created this row, if a member did.';
COMMENT ON COLUMN "MemberUsers"."created_by_admin_id" IS 'Staff account that created this row, if staff did.';
COMMENT ON COLUMN "MemberUsers"."updatedAt" IS 'Row last changed at.';
COMMENT ON COLUMN "MemberUsers"."updated_by_user_id" IS 'Member login that last changed this row.';
COMMENT ON COLUMN "MemberUsers"."updated_by_admin_id" IS 'Staff account that last changed this row.';

COMMENT ON TABLE "MemberTeamInvites" IS 'Outstanding invitations to join a company team; acceptance runs through the existing password-reset token path.';
COMMENT ON COLUMN "MemberTeamInvites"."id" IS 'Surrogate key.';
COMMENT ON COLUMN "MemberTeamInvites"."member_id" IS 'FK to Members.id. ON DELETE CASCADE.';
COMMENT ON COLUMN "MemberTeamInvites"."user_id" IS 'FK to Users.id — the login created for the invitee.';
COMMENT ON COLUMN "MemberTeamInvites"."email" IS 'Address the invite was sent to, as typed by the owner.';
COMMENT ON COLUMN "MemberTeamInvites"."full_name" IS 'Name as typed by the owner; copied onto Users.full_name.';
COMMENT ON COLUMN "MemberTeamInvites"."designation" IS 'Job title shown on the team screen and pre-filled into event attendee rows.';
COMMENT ON COLUMN "MemberTeamInvites"."invited_by_user_id" IS 'Member login that sent the invite.';
COMMENT ON COLUMN "MemberTeamInvites"."expires_at" IS 'When the invite stops being usable.';
COMMENT ON COLUMN "MemberTeamInvites"."accepted_at" IS 'Set when the invitee sets their password.';
COMMENT ON COLUMN "MemberTeamInvites"."revoked_at" IS 'Set when the owner cancels the invite.';
COMMENT ON COLUMN "MemberTeamInvites"."createdAt" IS 'Row created at.';
COMMENT ON COLUMN "MemberTeamInvites"."created_by_user_id" IS 'Member login that created this row.';
COMMENT ON COLUMN "MemberTeamInvites"."created_by_admin_id" IS 'Staff account that created this row.';
COMMENT ON COLUMN "MemberTeamInvites"."updatedAt" IS 'Row last changed at.';
COMMENT ON COLUMN "MemberTeamInvites"."updated_by_user_id" IS 'Member login that last changed this row.';
COMMENT ON COLUMN "MemberTeamInvites"."updated_by_admin_id" IS 'Staff account that last changed this row.';
```

- [ ] **Step 4: Apply and verify**

Run:
```bash
cd backend && npx prisma migrate dev && npx prisma migrate status && npm run db:check-comments
```
Expected: migration applies, `migrate status` reports no drift, `db:check-comments` prints zero rows.

- [ ] **Step 5: Verify the backfill and the owner constraint by hand**

Run:
```bash
cd backend && npx prisma db execute --stdin <<'SQL'
SELECT (SELECT count(*) FROM "Members" WHERE "primary_user_id" IS NOT NULL AND "deletedAt" IS NULL) AS members,
       (SELECT count(*) FROM "MemberUsers" WHERE "member_role" = 0) AS owner_rows;
SQL
```
Expected: the two counts are equal.

- [ ] **Step 6: Commit**

```bash
git add backend/prisma/schema/member.prisma backend/prisma/schema/identity.prisma backend/prisma/migrations
git commit -m "feat(m7): add MemberUsers and MemberTeamInvites with owner backfill"
```

---

### Task 2: Resolve a member through `MemberUsers`

This is the change that makes a team login see its company at all. Until it lands, an invited user logs in and sees nothing.

**Files:**
- Create: `backend/src/modules/member/team.constants.ts`
- Modify: `backend/src/modules/member/member.repository.ts:14-15`
- Test: `backend/src/modules/member/member.resolveTeam.test.ts`

**Interfaces:**
- Consumes: the Prisma models from Task 1.
- Produces: `MEMBER_ROLE`, `MEMBER_USER_STATUS` (const code maps) from `team.constants.ts`; `findMemberByUserId(db, userId)` keeps its existing signature `(db: Db, userId: bigint) => Promise<Member | null>` and its existing callers, so nothing downstream changes.

- [ ] **Step 1: Write the code maps**

Create `backend/src/modules/member/team.constants.ts`:

```ts
/**
 * Integer enum codes for the team tables.
 *
 * New tables use `smallint` codes rather than Postgres native enums (spec
 * section 0.1). Codes are append-only — a value is never reused, because old
 * rows keep the number that was written into them.
 */

export const MEMBER_ROLE = {
  /** The company's primary login. Exactly one per member, enforced by a partial unique index. */
  OWNER: 0,
  /** Anyone the owner invited. Finer permissions are deliberately deferred. */
  TEAM: 1,
} as const;

export type MemberRole = (typeof MEMBER_ROLE)[keyof typeof MEMBER_ROLE];

export const MEMBER_USER_STATUS = {
  /** Invite email sent; the password has not been set yet. Cannot act for the company. */
  INVITED: 0,
  /** Password set, login works. */
  ACTIVE: 1,
  /** Switched off by an owner. The row is kept for history rather than deleted. */
  DEACTIVATED: 2,
} as const;

export type MemberUserStatus = (typeof MEMBER_USER_STATUS)[keyof typeof MEMBER_USER_STATUS];

/** Statuses that may act on behalf of the company. */
export const ACTING_MEMBER_USER_STATUSES: number[] = [MEMBER_USER_STATUS.ACTIVE];
```

- [ ] **Step 2: Write the failing test**

Create `backend/src/modules/member/member.resolveTeam.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';

const memberFindFirst = vi.fn();

vi.mock('@db/prisma', () => ({
  prisma: { member: { findFirst: (...a: unknown[]) => memberFindFirst(...a) } },
}));

const { findMemberByUserId } = await import('@modules/member/member.repository');
const { MEMBER_USER_STATUS } = await import('@modules/member/team.constants');

const db = { member: { findFirst: memberFindFirst } } as never;

describe('findMemberByUserId', () => {
  it('resolves through MemberUsers, not primary_user_id, so a team login sees the company', async () => {
    memberFindFirst.mockResolvedValue({ id: 1042n });

    const result = await findMemberByUserId(db, 77n);

    expect(result).toEqual({ id: 1042n });

    const where = memberFindFirst.mock.calls[0][0].where;
    expect(where).toMatchObject({
      deletedAt: null,
      team_users: { some: { user_id: 77n, status: MEMBER_USER_STATUS.ACTIVE } },
    });
    expect(where).not.toHaveProperty('primary_user_id');
  });

  it('does not resolve a login that is only INVITED or DEACTIVATED', async () => {
    memberFindFirst.mockResolvedValue(null);

    const result = await findMemberByUserId(db, 78n);

    expect(result).toBeNull();
    expect(memberFindFirst.mock.calls[0][0].where.team_users.some.status).toBe(
      MEMBER_USER_STATUS.ACTIVE,
    );
  });
});
```

- [ ] **Step 3: Run the test and watch it fail**

Run: `cd backend && npx vitest run src/modules/member/member.resolveTeam.test.ts`
Expected: FAIL — the `where` still contains `primary_user_id` and has no `team_users`.

- [ ] **Step 4: Change the resolver**

Replace `backend/src/modules/member/member.repository.ts` lines 14-15 with:

```ts
/**
 * The company a signed-in member belongs to.
 *
 * Resolution goes through `MemberUsers`, not `Members.primary_user_id`, because a
 * company can have several logins (the owner plus invited team members) and all of
 * them must land on the same company record. Only ACTIVE rows resolve: an INVITED
 * user has not set a password yet and a DEACTIVATED one has been switched off, and
 * neither may act for the firm.
 */
export const findMemberByUserId = (db: Db, userId: bigint) =>
  db.member.findFirst({
    where: {
      deletedAt: null,
      team_users: { some: { user_id: userId, status: MEMBER_USER_STATUS.ACTIVE } },
    },
  });
```

Add the import at the top of the file:

```ts
import { MEMBER_USER_STATUS } from '@modules/member/team.constants';
```

- [ ] **Step 5: Run the test and the whole suite**

Run: `cd backend && npx vitest run && npm run typecheck`
Expected: both pass. If another test broke, it was relying on `primary_user_id` resolution — fix that test to seed a `MemberUsers` row instead of changing the resolver back.

- [ ] **Step 6: Commit**

```bash
git add backend/src/modules/member/team.constants.ts backend/src/modules/member/member.repository.ts backend/src/modules/member/member.resolveTeam.test.ts
git commit -m "feat(m7): resolve a member through MemberUsers so team logins see their company"
```

---

### Task 3: Read the team roster — `GET /members/me/team`

**Files:**
- Create: `backend/src/modules/member/team.repository.ts`
- Create: `backend/src/modules/member/team.service.ts`
- Create: `backend/src/modules/member/team.controller.ts`
- Modify: `backend/src/modules/member/member.routes.ts` (append routes at the end of `memberRouter`)
- Test: `backend/src/modules/member/team.list.test.ts`

**Interfaces:**
- Consumes: `MEMBER_ROLE`, `MEMBER_USER_STATUS` from Task 2.
- Produces:
  - `listTeam(memberId: bigint): Promise<TeamMemberRow[]>`
  - `type TeamMemberRow = { id: string; user_id: string; full_name: string; email: string; designation: string | null; member_role: number; status: number; accepted_at: Date | null }`
  - Task 4 and Task 6 import `TeamMemberRow` and the repository helpers from these same files.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/member/team.list.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';

const queryRaw = vi.fn();

vi.mock('@db/prisma', () => ({ prisma: { $queryRaw: (...a: unknown[]) => queryRaw(...a) } }));

const { listTeam } = await import('@modules/member/team.service');

describe('listTeam', () => {
  it('returns the roster with the owner first', async () => {
    queryRaw.mockResolvedValue([
      {
        id: 1n,
        user_id: 10n,
        full_name: 'Ramesh Shah',
        email: 'ramesh@abc.com',
        designation: 'Director',
        member_role: 0,
        status: 1,
        accepted_at: new Date('2026-01-01'),
      },
      {
        id: 2n,
        user_id: 11n,
        full_name: 'Priya Mehta',
        email: 'priya@abc.com',
        designation: 'Manager',
        member_role: 1,
        status: 0,
        accepted_at: null,
      },
    ]);

    const rows = await listTeam(1042n);

    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ id: '1', member_role: 0, full_name: 'Ramesh Shah' });
    expect(rows[1]).toMatchObject({ id: '2', status: 0, accepted_at: null });
  });

  it('returns an empty array rather than throwing when a firm has no rows', async () => {
    queryRaw.mockResolvedValue([]);

    await expect(listTeam(9999n)).resolves.toEqual([]);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd backend && npx vitest run src/modules/member/team.list.test.ts`
Expected: FAIL — `Cannot find module '@modules/member/team.service'`.

- [ ] **Step 3: Write the repository**

Create `backend/src/modules/member/team.repository.ts`:

```ts
import { Prisma } from '@prisma/client';
import { prisma } from '@db/prisma';
import type { Db } from '@db/prisma';

/**
 * Data access for company team logins.
 *
 * The roster is one raw statement joining `Users`, because the screen needs the
 * login's name and email next to the team row and Prisma's nested include would
 * return a shape the controller then has to flatten anyway (ADR-005).
 */

export interface TeamMemberRow {
  id: string;
  user_id: string;
  full_name: string;
  email: string;
  designation: string | null;
  member_role: number;
  status: number;
  accepted_at: Date | null;
}

interface TeamMemberDbRow extends Omit<TeamMemberRow, 'id' | 'user_id'> {
  id: bigint;
  user_id: bigint;
}

/** The roster for one firm: owner first, then everyone else oldest to newest. */
export const findTeamByMemberId = async (memberId: bigint): Promise<TeamMemberDbRow[]> =>
  prisma.$queryRaw<TeamMemberDbRow[]>(Prisma.sql`
    SELECT mu."id",
           mu."user_id",
           u."full_name",
           u."email"::text AS email,
           i."designation",
           mu."member_role",
           mu."status",
           mu."accepted_at"
      FROM "MemberUsers" mu
      JOIN "Users" u ON u."id" = mu."user_id"
      LEFT JOIN LATERAL (
        SELECT ti."designation"
          FROM "MemberTeamInvites" ti
         WHERE ti."user_id" = mu."user_id"
           AND ti."member_id" = mu."member_id"
         ORDER BY ti."createdAt" DESC
         LIMIT 1
      ) i ON TRUE
     WHERE mu."member_id" = ${memberId}
     ORDER BY mu."member_role" ASC, mu."id" ASC
  `);

/** One team row, scoped to the firm so a caller can never touch another company's. */
export const findTeamRow = (db: Db, memberId: bigint, id: bigint) =>
  db.memberUser.findFirst({ where: { id, member_id: memberId } });

/** Is this login already on this firm's roster, in any status? */
export const findTeamRowByUserId = (db: Db, memberId: bigint, userId: bigint) =>
  db.memberUser.findFirst({ where: { member_id: memberId, user_id: userId } });
```

- [ ] **Step 4: Write the service**

Create `backend/src/modules/member/team.service.ts`:

```ts
import * as repo from '@modules/member/team.repository';
import type { TeamMemberRow } from '@modules/member/team.repository';

/**
 * The company's team roster.
 *
 * BigInt ids are serialised to strings at this boundary because JSON has no
 * bigint and the encryption layer stringifies the payload before it ever reaches
 * a custom replacer.
 */
export const listTeam = async (memberId: bigint): Promise<TeamMemberRow[]> => {
  const rows = await repo.findTeamByMemberId(memberId);

  return rows.map((row) => ({
    ...row,
    id: row.id.toString(),
    user_id: row.user_id.toString(),
  }));
};
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `cd backend && npx vitest run src/modules/member/team.list.test.ts`
Expected: PASS, both cases.

- [ ] **Step 6: Wire the controller and the route**

Create `backend/src/modules/member/team.controller.ts`:

```ts
import { handler } from '@utils/handler';
import * as service from '@modules/member/team.service';
import { requireMemberContext } from '@modules/member/team.context';

/** `GET /members/me/team` — the company's own roster (C-15 Team tab). */
export const listTeam = handler(async (req, res) => {
  const { memberId } = await requireMemberContext(req);

  res.success({ rows: await service.listTeam(memberId) });
});
```

Create `backend/src/modules/member/team.context.ts`:

```ts
import { AppError } from '@utils/appError';
import { ERROR_TYPES } from '@constant';
import { prisma } from '@db/prisma';
import * as memberRepo from '@modules/member/member.repository';
import * as teamRepo from '@modules/member/team.repository';
import { MEMBER_ROLE } from '@modules/member/team.constants';
import type { Request } from 'express';

export interface MemberContext {
  memberId: bigint;
  userId: bigint;
  isOwner: boolean;
}

/**
 * The company and role behind a member request.
 *
 * Every team endpoint needs the same three facts, and getting them wrong means a
 * user acting on another firm's roster — so the lookup lives in one place rather
 * than being repeated per controller.
 */
export const requireMemberContext = async (req: Request): Promise<MemberContext> => {
  const userId = req.user?.id;

  if (!userId) {
    throw new AppError({ errorType: ERROR_TYPES.UNAUTHORIZED, messageKey: 'auth.invalidToken' });
  }

  const member = await memberRepo.findMemberByUserId(prisma, userId);

  if (!member) {
    throw new AppError({ errorType: ERROR_TYPES.FORBIDDEN, messageKey: 'member.noMemberRecord' });
  }

  const row = await teamRepo.findTeamRowByUserId(prisma, member.id, userId);

  return {
    memberId: member.id,
    userId,
    isOwner: row?.member_role === MEMBER_ROLE.OWNER,
  };
};

/** Throws unless the caller is the firm's OWNER. Team-member permissions are deferred. */
export const requireOwner = (context: MemberContext): void => {
  if (!context.isOwner) {
    throw new AppError({ errorType: ERROR_TYPES.FORBIDDEN, messageKey: 'member.teamOwnerOnly' });
  }
};
```

Add to `backend/src/modules/member/member.routes.ts` — import at the top:

```ts
import * as teamController from '@modules/member/team.controller';
```

and append after the contacts routes:

```ts
memberRouter.get('/me/team', teamController.listTeam);
```

Add the two message keys to `backend/src/locales/en.json` (or whichever file `member.noMemberRecord` siblings live in — grep for an existing `member.` key and add alongside it):

```json
"member.teamOwnerOnly": "Only the company owner can manage team logins."
```

- [ ] **Step 7: Verify end to end**

Run: `cd backend && npm run typecheck && npx vitest run`
Expected: PASS. Then start the server and call `GET /api/v1/members/me/team` with an existing member's token; expect a single OWNER row (from the Task 1 backfill).

- [ ] **Step 8: Commit**

```bash
git add backend/src/modules/member/team.*.ts backend/src/modules/member/member.routes.ts backend/src/locales
git commit -m "feat(m7): expose the company team roster"
```

---

### Task 4: Invite a team member — `POST /members/me/team`

**Files:**
- Modify: `backend/src/modules/member/team.types.ts` (create)
- Modify: `backend/src/modules/member/team.service.ts` (add `inviteTeamMember`)
- Modify: `backend/src/modules/member/team.repository.ts` (add writes)
- Modify: `backend/src/modules/member/team.controller.ts`
- Modify: `backend/src/modules/member/member.routes.ts`
- Modify: `backend/src/constant/audit.constant.ts`
- Modify: `backend/prisma/seed/notificationTemplates.ts`
- Test: `backend/src/modules/member/team.invite.test.ts`

**Interfaces:**
- Consumes: `requireMemberContext`, `requireOwner` (Task 3); `issueInitialPasswordLink(tx, user, context)` from `@modules/auth/auth.service`; `contextFromRequest(req)` from the same module.
- Produces: `inviteTeamMember(input: InviteTeamMemberInput, context: MemberContext, request: RequestContext): Promise<TeamMemberRow>`.

- [ ] **Step 1: Write the validation schema**

Create `backend/src/modules/member/team.types.ts`:

```ts
import { z } from 'zod';

/** Body of `POST /members/me/team`. */
export const inviteTeamMemberSchema = z.object({
  full_name: z.string().trim().min(2).max(150),
  email: z.string().trim().toLowerCase().email().max(200),
  designation: z.string().trim().max(100).optional(),
});

export type InviteTeamMemberInput = z.infer<typeof inviteTeamMemberSchema>;

/** Body of `PATCH /members/me/team/:id/status`. */
export const teamStatusSchema = z.object({
  active: z.boolean(),
});

export type TeamStatusInput = z.infer<typeof teamStatusSchema>;
```

- [ ] **Step 2: Write the failing test**

Create `backend/src/modules/member/team.invite.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const findUserByEmail = vi.fn();
const findTeamRowByUserId = vi.fn();
const createUser = vi.fn();
const createTeamRow = vi.fn();
const createInvite = vi.fn();
const issueInitialPasswordLink = vi.fn();
const writeAudit = vi.fn();

vi.mock('@db/prisma', () => ({
  prisma: { $transaction: async (fn: (tx: unknown) => unknown) => fn({}) },
}));
vi.mock('@modules/member/team.repository', () => ({
  findTeamRowByUserId: (...a: unknown[]) => findTeamRowByUserId(...a),
  createTeamRow: (...a: unknown[]) => createTeamRow(...a),
  createInvite: (...a: unknown[]) => createInvite(...a),
  findUserByEmail: (...a: unknown[]) => findUserByEmail(...a),
  createUser: (...a: unknown[]) => createUser(...a),
}));
vi.mock('@modules/auth/auth.service', () => ({
  issueInitialPasswordLink: (...a: unknown[]) => issueInitialPasswordLink(...a),
}));
vi.mock('@utils/audit', () => ({ writeAudit: (...a: unknown[]) => writeAudit(...a) }));

const { inviteTeamMember } = await import('@modules/member/team.service');

const ctx = { memberId: 1042n, userId: 10n, isOwner: true };
const req = { ip: '127.0.0.1', userAgent: 'test', requestId: 'r1' };

beforeEach(() => {
  vi.clearAllMocks();
  findUserByEmail.mockResolvedValue(null);
  createUser.mockResolvedValue({ id: 11n, email: 'priya@abc.com', full_name: 'Priya Mehta' });
  createTeamRow.mockResolvedValue({ id: 2n, user_id: 11n, member_role: 1, status: 0 });
  createInvite.mockResolvedValue({ id: 5n });
});

describe('inviteTeamMember', () => {
  it('creates a passwordless login, an INVITED team row, and sends the set-password link', async () => {
    const result = await inviteTeamMember(
      { full_name: 'Priya Mehta', email: 'priya@abc.com', designation: 'Manager' },
      ctx,
      req,
    );

    expect(createUser).toHaveBeenCalledOnce();
    expect(createUser.mock.calls[0][1]).toMatchObject({ password_hash: null });

    expect(createTeamRow.mock.calls[0][1]).toMatchObject({
      member_id: 1042n,
      user_id: 11n,
      member_role: 1,
      status: 0,
      invited_by_user_id: 10n,
      created_by_user_id: 10n,
    });

    expect(issueInitialPasswordLink).toHaveBeenCalledOnce();
    expect(result).toMatchObject({ id: '2', status: 0 });
  });

  it('rejects an address that is already on this firm\'s roster', async () => {
    findUserByEmail.mockResolvedValue({ id: 11n, email: 'priya@abc.com', full_name: 'Priya' });
    findTeamRowByUserId.mockResolvedValue({ id: 2n });

    await expect(
      inviteTeamMember({ full_name: 'Priya Mehta', email: 'priya@abc.com' }, ctx, req),
    ).rejects.toThrow(/already/i);

    expect(createTeamRow).not.toHaveBeenCalled();
  });

  it('rejects an address that already belongs to a different company', async () => {
    findUserByEmail.mockResolvedValue({ id: 99n, email: 'x@other.com', full_name: 'X' });
    findTeamRowByUserId.mockResolvedValue(null);

    await expect(
      inviteTeamMember({ full_name: 'X', email: 'x@other.com' }, ctx, req),
    ).rejects.toThrow(/in use/i);

    expect(createUser).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 3: Run it and watch it fail**

Run: `cd backend && npx vitest run src/modules/member/team.invite.test.ts`
Expected: FAIL — `inviteTeamMember is not a function`.

- [ ] **Step 4: Add the repository writes**

Append to `backend/src/modules/member/team.repository.ts`:

```ts
import { UserStatus } from '@prisma/client';

/** Any login already using this address, across all companies. */
export const findUserByEmail = (db: Db, email: string) =>
  db.user.findFirst({ where: { email, deletedAt: null } });

/**
 * A login with no password yet.
 *
 * `password_hash` stays null until the invitee follows the emailed link, which is
 * exactly the state `setInitialPassword` refuses to run twice against — so an
 * invite link cannot be replayed to overwrite a working password.
 */
export const createUser = (
  db: Db,
  data: { email: string; full_name: string },
) =>
  db.user.create({
    data: {
      email: data.email,
      full_name: data.full_name,
      password_hash: null,
      status: UserStatus.PENDING_VERIFICATION,
    },
  });

export const createTeamRow = (
  db: Db,
  data: {
    member_id: bigint;
    user_id: bigint;
    member_role: number;
    status: number;
    invited_by_user_id: bigint;
    created_by_user_id: bigint;
  },
) => db.memberUser.create({ data });

export const createInvite = (
  db: Db,
  data: {
    member_id: bigint;
    user_id: bigint;
    email: string;
    full_name: string;
    designation?: string | null;
    invited_by_user_id: bigint;
    expires_at: Date;
    created_by_user_id: bigint;
  },
) => db.memberTeamInvite.create({ data });

export const updateTeamRow = (
  db: Db,
  id: bigint,
  data: { status?: number; accepted_at?: Date | null; deactivated_at?: Date | null; updated_by_user_id?: bigint },
) => db.memberUser.update({ where: { id }, data });
```

- [ ] **Step 5: Write the service**

Append to `backend/src/modules/member/team.service.ts`:

```ts
import { prisma } from '@db/prisma';
import { AppError } from '@utils/appError';
import { writeAudit } from '@utils/audit';
import { ACTOR_TYPES, AUDIT_ACTIONS, ERROR_TYPES } from '@constant';
import { issueInitialPasswordLink } from '@modules/auth/auth.service';
import { MEMBER_ROLE, MEMBER_USER_STATUS } from '@modules/member/team.constants';
import type { MemberContext } from '@modules/member/team.context';
import type { InviteTeamMemberInput } from '@modules/member/team.types';
import type { RequestContext } from '@modules/auth/auth.service';

/** How long a team invite link stays usable. Matches the password-reset window. */
const INVITE_EXPIRY_HOURS = 48;

/**
 * Invite someone onto the company's roster.
 *
 * The login is created without a password and the invitee sets it through the
 * existing `setInitialPassword` link. Reusing that path rather than inventing an
 * invite-token flow means one password-setting code path, one expiry rule, and
 * one place where a token can be replayed — instead of two.
 */
export const inviteTeamMember = async (
  input: InviteTeamMemberInput,
  context: MemberContext,
  request: RequestContext,
) => {
  const existing = await repo.findUserByEmail(prisma, input.email);

  if (existing) {
    const onThisTeam = await repo.findTeamRowByUserId(prisma, context.memberId, existing.id);

    throw new AppError({
      errorType: ERROR_TYPES.CONFLICT,
      messageKey: onThisTeam ? 'member.teamEmailAlreadyOnTeam' : 'member.teamEmailInUse',
    });
  }

  return prisma.$transaction(async (tx) => {
    const user = await repo.createUser(tx, {
      email: input.email,
      full_name: input.full_name,
    });

    const row = await repo.createTeamRow(tx, {
      member_id: context.memberId,
      user_id: user.id,
      member_role: MEMBER_ROLE.TEAM,
      status: MEMBER_USER_STATUS.INVITED,
      invited_by_user_id: context.userId,
      created_by_user_id: context.userId,
    });

    await repo.createInvite(tx, {
      member_id: context.memberId,
      user_id: user.id,
      email: input.email,
      full_name: input.full_name,
      designation: input.designation ?? null,
      invited_by_user_id: context.userId,
      expires_at: new Date(Date.now() + INVITE_EXPIRY_HOURS * 3_600_000),
      created_by_user_id: context.userId,
    });

    await issueInitialPasswordLink(tx, user, request);

    await writeAudit(tx, {
      action: AUDIT_ACTIONS.MEMBER_TEAM_INVITED,
      entityName: 'MemberUsers',
      entityId: row.id,
      actorType: ACTOR_TYPES.MEMBER,
      actorId: context.userId,
      after: { email: input.email, member_role: MEMBER_ROLE.TEAM },
      ip: request.ip,
      userAgent: request.userAgent,
      requestId: request.requestId,
    });

    return {
      id: row.id.toString(),
      user_id: user.id.toString(),
      full_name: input.full_name,
      email: input.email,
      designation: input.designation ?? null,
      member_role: MEMBER_ROLE.TEAM,
      status: MEMBER_USER_STATUS.INVITED,
      accepted_at: null,
    };
  });
};
```

- [ ] **Step 6: Add the audit action and the messages**

In `backend/src/constant/audit.constant.ts`, alongside the other member actions:

```ts
  // --- M7: company team logins ----------------------------------------------
  /** An owner invited someone onto the company roster. */
  MEMBER_TEAM_INVITED: 'member_team.invited',
  /** An owner switched a team login on or off. */
  MEMBER_TEAM_STATUS_CHANGED: 'member_team.status_changed',
  /** An invitee set their password and joined the roster. */
  MEMBER_TEAM_ACCEPTED: 'member_team.accepted',
```

Add to the locale file next to `member.teamOwnerOnly`:

```json
"member.teamEmailAlreadyOnTeam": "That email is already on your team.",
"member.teamEmailInUse": "That email is already in use on this platform."
```

- [ ] **Step 7: Run the test**

Run: `cd backend && npx vitest run src/modules/member/team.invite.test.ts`
Expected: PASS, all three cases.

- [ ] **Step 8: Wire the route**

In `team.controller.ts`:

```ts
import { contextFromRequest } from '@modules/auth/auth.service';
import { requireOwner } from '@modules/member/team.context';
import { CREATED } from '@constant';

/** `POST /members/me/team` — invite a colleague. Owner only. */
export const inviteTeamMember = handler(async (req, res) => {
  const context = await requireMemberContext(req);
  requireOwner(context);

  const row = await service.inviteTeamMember(req.body, context, contextFromRequest(req));

  res.success({ row }, { status: 201 });
});
```

(If `res.success` does not take a status option in this codebase, grep `member.controller.ts` for an existing 201 response and copy that call shape exactly.)

In `member.routes.ts`:

```ts
memberRouter.post(
  '/me/team',
  validateRequest({ body: inviteTeamMemberSchema }),
  teamController.inviteTeamMember,
);
```

with `import { inviteTeamMemberSchema, teamStatusSchema } from '@modules/member/team.types';`

- [ ] **Step 9: Add the invite email template**

In `backend/prisma/seed/notificationTemplates.ts`, add next to `auth.password_reset`:

```ts
  {
    code: 'member.team_invite',
    channel: NotificationChannel.EMAIL,
    locale: 'en',
    subject: 'You have been added to {{company_name}}',
    body: [
      'Hello {{full_name}},',
      '',
      '{{inviter_name}} has added you to {{company_name}} on the association portal.',
      '',
      'Set your password using the link below. It expires in {{expiry_hours}} hours.',
      '',
      '{{reset_url}}',
      '',
      'If you were not expecting this, you can ignore this email.',
    ].join('\n'),
  },
```

> **Note for the implementer:** Step 5 sends `auth.password_reset` via `issueInitialPasswordLink`, which is correct and working. Wiring this friendlier template is a follow-up inside Task 4 only if `issueInitialPasswordLink` accepts a template override; if it does not, seed the template now and leave the override to the event module's notification work rather than changing a shared auth function.

- [ ] **Step 10: Verify and commit**

Run: `cd backend && npm run typecheck && npx vitest run && npx prisma db seed`
Expected: all pass; the new template row exists.

```bash
git add backend/src/modules/member backend/src/constant/audit.constant.ts backend/src/locales backend/prisma/seed/notificationTemplates.ts
git commit -m "feat(m7): invite a colleague onto the company team"
```

---

### Task 5: Accepting an invite activates the team row

**Files:**
- Modify: `backend/src/modules/auth/auth.service.ts:904-950` (`setInitialPassword`)
- Test: `backend/src/modules/member/team.accept.test.ts`

**Interfaces:**
- Consumes: `MEMBER_USER_STATUS` (Task 2), `updateTeamRow` (Task 4).
- Produces: no new exports. `setInitialPassword` keeps its signature; it gains a side effect inside its existing transaction.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/member/team.accept.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const activateTeamRowForUser = vi.fn();

vi.mock('@modules/member/team.repository', () => ({
  activateTeamRowForUser: (...a: unknown[]) => activateTeamRowForUser(...a),
}));

const { activateInvitedTeamRow } = await import('@modules/member/team.activation');

beforeEach(() => vi.clearAllMocks());

describe('activateInvitedTeamRow', () => {
  it('flips an INVITED row to ACTIVE and stamps accepted_at', async () => {
    activateTeamRowForUser.mockResolvedValue({ count: 1 });

    await activateInvitedTeamRow({} as never, 11n);

    const args = activateTeamRowForUser.mock.calls[0];
    expect(args[1]).toBe(11n);
  });

  it('is a no-op for a login that was never invited to a team', async () => {
    activateTeamRowForUser.mockResolvedValue({ count: 0 });

    await expect(activateInvitedTeamRow({} as never, 12n)).resolves.toBeUndefined();
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd backend && npx vitest run src/modules/member/team.accept.test.ts`
Expected: FAIL — module `@modules/member/team.activation` not found.

- [ ] **Step 3: Add the repository write and the activation helper**

Append to `backend/src/modules/member/team.repository.ts`:

```ts
/**
 * Activate every INVITED row for this login.
 *
 * Scoped to INVITED so replaying a link cannot resurrect a DEACTIVATED person,
 * and written as `updateMany` so a login with no team row is a no-op rather than
 * a thrown "record not found".
 */
export const activateTeamRowForUser = (db: Db, userId: bigint, now: Date) =>
  db.memberUser.updateMany({
    where: { user_id: userId, status: MEMBER_USER_STATUS.INVITED },
    data: { status: MEMBER_USER_STATUS.ACTIVE, accepted_at: now },
  });

/** Mark the matching open invite accepted, so it stops showing as pending. */
export const acceptInvitesForUser = (db: Db, userId: bigint, now: Date) =>
  db.memberTeamInvite.updateMany({
    where: { user_id: userId, accepted_at: null, revoked_at: null },
    data: { accepted_at: now },
  });
```

Add the import `import { MEMBER_USER_STATUS } from '@modules/member/team.constants';` at the top of the repository.

Create `backend/src/modules/member/team.activation.ts`:

```ts
import * as repo from '@modules/member/team.repository';
import type { Db } from '@db/prisma';

/**
 * Turn an accepted invite into a working team login.
 *
 * Called from `setInitialPassword` inside its existing transaction, so the
 * password and the roster row commit together: a user can never end up able to
 * sign in while still showing as INVITED, or vice versa.
 */
export const activateInvitedTeamRow = async (tx: Db, userId: bigint): Promise<void> => {
  const now = new Date();

  await repo.activateTeamRowForUser(tx, userId, now);
  await repo.acceptInvitesForUser(tx, userId, now);
};
```

- [ ] **Step 4: Call it from `setInitialPassword`**

In `backend/src/modules/auth/auth.service.ts`, inside the `prisma.$transaction` in `setInitialPassword`, immediately after `repo.updateUser(...)` and before `writeAudit(...)`:

```ts
    // A team invite and a post-approval password link are the same email. If this
    // login was invited onto a company roster, the row goes ACTIVE in the same
    // transaction as the password — never one without the other.
    await activateInvitedTeamRow(tx, user.id);
```

with the import `import { activateInvitedTeamRow } from '@modules/member/team.activation';`.

- [ ] **Step 5: Run the tests**

Run: `cd backend && npx vitest run && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Verify by hand**

Invite a colleague through `POST /members/me/team`, take the token out of the outbox (`npm run otp` shows codes; for the reset link read the `Notifications` row payload), set a password through the existing set-password endpoint, then call `GET /members/me/team` as the new login.
Expected: the row reads `status: 1`, `accepted_at` is set, and `GET /members/me` returns the **same company** as the owner sees.

- [ ] **Step 7: Commit**

```bash
git add backend/src/modules/member/team.activation.ts backend/src/modules/member/team.repository.ts backend/src/modules/auth/auth.service.ts backend/src/modules/member/team.accept.test.ts
git commit -m "feat(m7): activate the team row when an invitee sets their password"
```

---

### Task 6: Switch a team member on or off

**Files:**
- Modify: `backend/src/modules/member/team.service.ts`
- Modify: `backend/src/modules/member/team.controller.ts`
- Modify: `backend/src/modules/member/member.routes.ts`
- Test: `backend/src/modules/member/team.status.test.ts`

**Interfaces:**
- Consumes: `requireOwner`, `findTeamRow`, `updateTeamRow`, `MEMBER_ROLE`, `MEMBER_USER_STATUS`.
- Produces: `setTeamMemberStatus(id: bigint, input: TeamStatusInput, context: MemberContext, request: RequestContext): Promise<{ id: string; status: number }>`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/member/team.status.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const findTeamRow = vi.fn();
const updateTeamRow = vi.fn();
const writeAudit = vi.fn();

vi.mock('@db/prisma', () => ({
  prisma: { $transaction: async (fn: (tx: unknown) => unknown) => fn({}) },
}));
vi.mock('@modules/member/team.repository', () => ({
  findTeamRow: (...a: unknown[]) => findTeamRow(...a),
  updateTeamRow: (...a: unknown[]) => updateTeamRow(...a),
}));
vi.mock('@utils/audit', () => ({ writeAudit: (...a: unknown[]) => writeAudit(...a) }));

const { setTeamMemberStatus } = await import('@modules/member/team.service');

const ctx = { memberId: 1042n, userId: 10n, isOwner: true };
const req = { ip: '127.0.0.1', userAgent: 'test', requestId: 'r1' };

beforeEach(() => {
  vi.clearAllMocks();
  updateTeamRow.mockResolvedValue({ id: 2n, status: 2 });
});

describe('setTeamMemberStatus', () => {
  it('deactivates a team row and stamps deactivated_at', async () => {
    findTeamRow.mockResolvedValue({ id: 2n, member_role: 1, status: 1 });

    const result = await setTeamMemberStatus(2n, { active: false }, ctx, req);

    expect(updateTeamRow.mock.calls[0][2]).toMatchObject({ status: 2 });
    expect(updateTeamRow.mock.calls[0][2].deactivated_at).toBeInstanceOf(Date);
    expect(result).toMatchObject({ id: '2', status: 2 });
  });

  it('refuses to deactivate the OWNER — a company must always have one', async () => {
    findTeamRow.mockResolvedValue({ id: 1n, member_role: 0, status: 1 });

    await expect(setTeamMemberStatus(1n, { active: false }, ctx, req)).rejects.toThrow(/owner/i);

    expect(updateTeamRow).not.toHaveBeenCalled();
  });

  it('refuses a row belonging to another company', async () => {
    findTeamRow.mockResolvedValue(null);

    await expect(setTeamMemberStatus(999n, { active: false }, ctx, req)).rejects.toThrow(
      /not found/i,
    );
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd backend && npx vitest run src/modules/member/team.status.test.ts`
Expected: FAIL — `setTeamMemberStatus is not a function`.

- [ ] **Step 3: Write the service**

Append to `backend/src/modules/member/team.service.ts`:

```ts
/**
 * Switch a colleague's login on or off.
 *
 * The OWNER row is refused outright: `findMemberByUserId` only resolves ACTIVE
 * rows, so deactivating the owner would lock the company out of its own account
 * with no way back in from the member side.
 */
export const setTeamMemberStatus = async (
  id: bigint,
  input: TeamStatusInput,
  context: MemberContext,
  request: RequestContext,
) => {
  const row = await repo.findTeamRow(prisma, context.memberId, id);

  if (!row) {
    throw new AppError({ errorType: ERROR_TYPES.NOT_FOUND, messageKey: 'member.teamRowNotFound' });
  }

  if (row.member_role === MEMBER_ROLE.OWNER) {
    throw new AppError({
      errorType: ERROR_TYPES.VALIDATION_ERROR,
      messageKey: 'member.teamCannotDeactivateOwner',
    });
  }

  const nextStatus = input.active ? MEMBER_USER_STATUS.ACTIVE : MEMBER_USER_STATUS.DEACTIVATED;

  return prisma.$transaction(async (tx) => {
    const updated = await repo.updateTeamRow(tx, id, {
      status: nextStatus,
      deactivated_at: input.active ? null : new Date(),
      updated_by_user_id: context.userId,
    });

    await writeAudit(tx, {
      action: AUDIT_ACTIONS.MEMBER_TEAM_STATUS_CHANGED,
      entityName: 'MemberUsers',
      entityId: id,
      actorType: ACTOR_TYPES.MEMBER,
      actorId: context.userId,
      before: { status: row.status },
      after: { status: nextStatus },
      ip: request.ip,
      userAgent: request.userAgent,
      requestId: request.requestId,
    });

    return { id: updated.id.toString(), status: updated.status };
  });
};
```

Add the imports `TeamStatusInput` and `MEMBER_ROLE` to the existing import lines at the top of the file.

Add the messages:

```json
"member.teamRowNotFound": "That team member was not found.",
"member.teamCannotDeactivateOwner": "The company owner cannot be deactivated."
```

- [ ] **Step 4: Run the test**

Run: `cd backend && npx vitest run src/modules/member/team.status.test.ts`
Expected: PASS, all three cases.

- [ ] **Step 5: Wire the route**

In `team.controller.ts`:

```ts
/** `PATCH /members/me/team/:id/status` — switch a colleague on or off. Owner only. */
export const setTeamMemberStatus = handler(async (req, res) => {
  const context = await requireMemberContext(req);
  requireOwner(context);

  const row = await service.setTeamMemberStatus(
    BigInt(req.params.id),
    req.body,
    context,
    contextFromRequest(req),
  );

  res.success({ row });
});
```

In `member.routes.ts`:

```ts
memberRouter.patch(
  '/me/team/:id/status',
  validateRequest({ params: idParamSchema, body: teamStatusSchema }),
  teamController.setTeamMemberStatus,
);
```

- [ ] **Step 6: Verify and commit**

Run: `cd backend && npm run typecheck && npx vitest run`
Expected: PASS.

```bash
git add backend/src/modules/member backend/src/locales
git commit -m "feat(m7): activate and deactivate company team logins"
```

---

### Task 7: Customer Team screen

**Files:**
- Create: `customer/src/app/(member)/profile/team/page.tsx`
- Create: `customer/src/components/profile/TeamTable.tsx`
- Create: `customer/src/components/profile/InviteTeamMemberForm.tsx`
- Modify: the profile navigation (grep `customer/src/app/(member)/profile` for the existing tab list and add "Team")

**Interfaces:**
- Consumes: `GET /members/me/team`, `POST /members/me/team`, `PATCH /members/me/team/:id/status`.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Read the existing patterns before writing anything**

Run:
```bash
cd customer && ls src/app/\(member\)/profile && sed -n '1,80p' src/components/profile/*.tsx | head -120
```
Follow whatever the contacts screen already does for fetching, error display and toasts. Do not introduce a new data-fetching approach.

- [ ] **Step 2: Build the roster table**

`TeamTable.tsx` renders the four columns the API returns, and states must read as plain English, not as codes:

| `status` | Chip shown |
|---|---|
| 0 | "Invitation sent" |
| 1 | "Active" |
| 2 | "Deactivated" |

`member_role === 0` renders an "Owner" chip and **no** status toggle — the API refuses it, so the UI must not offer it.

- [ ] **Step 3: Build the invite form**

Three fields — full name, email, designation — matching `inviteTeamMemberSchema` exactly. On success, show: *"Invitation sent to {email}. They will appear as Active once they set their password."* This is the Current State → Required Action → Next Step → Expected Result rule from CLAUDE.md; do not ship a bare "Saved" toast.

On a 409, show the API's message directly — the two cases ("already on your team" vs "already in use") mean different things to the user.

- [ ] **Step 4: Verify in the browser**

Run the customer app, sign in as an existing member, open Profile → Team.
Expected: one Owner row (from the backfill). Invite a colleague, confirm the row appears as "Invitation sent", accept the emailed link in another browser profile, refresh, confirm it flips to "Active".

- [ ] **Step 5: Commit**

```bash
git add customer/src
git commit -m "feat(m7): company team screen in the customer app"
```

---

## Self-review

**Spec coverage.** Schema section 1 (`MemberUsers`, `MemberTeamInvites`) → Task 1. Section 0.1 integer enums → Task 1 + Task 2 code maps. 0.2 bigint / 0.3 no uuid → Task 1. 0.4 FK actions → Task 1. 0.5 transaction-wrapped migration → Task 1 Step 3. 0.6 comments → Task 1 Step 3-4. 0.7 audit block → Task 1. Design section 2 (owner invites, invitee sets own password, one membership many logins) → Tasks 4, 5, 7. The attendee picker that consumes this roster belongs to the event plan, not here.

**Deferred on purpose.** Team-member permissions beyond "owner manages the roster" — the user parked this. `requireOwner` is the single place to widen when they decide.

**Known gap, flagged not hidden.** Task 4 Step 9 seeds a friendlier invite template but the invite email actually sent is `auth.password_reset`, because switching it means changing a shared auth function used by the approval flow. That is called out in the task rather than silently left as a TODO.
