# Guest Booking Verification and Member Linking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify a guest's company email by OTP at event booking, attach those bookings to the member account when the approved applicant first signs in, and give guests an OTP-gated page listing every booking and invoice made with their email — all behind admin switches that default to off.

**Architecture:** Ownership is never rewritten. `EventRegistration` and `Invoice` each carry a CHECK constraint requiring exactly one of `member_id` / `guest_registrant_id`, so guest rows stay guest-owned for life. Linking adds `GuestRegistrant.linked_member_id` and member read paths follow that pointer. Every behaviour change is gated on a `SystemSettings` boolean read through `getBooleanSetting(key, false)`, so the deployed system behaves exactly as it does today until an admin flips a switch.

**Tech Stack:** Node 20 + Express + TypeScript, Prisma 6 / PostgreSQL, Zod, vitest, bcryptjs, jsonwebtoken. Customer app is Next.js 15 App Router + Redux Toolkit.

**Spec:** `docs/superpowers/specs/2026-09-09-guest-booking-linking-design.md`

## Global Constraints

- **Both flags default to `false`.** `events.guest_booking_otp` and `events.booking_lookup_enabled`. With both off, no request may take a different code path than it does today. This is the single most important property of this work.
- **`otp_code` is OPTIONAL in the Zod schema.** Required-ness is enforced in the service, only when the flag is on. A required schema field would reject every booking from a frontend that has not shipped yet.
- **Never mutate `EventRegistration.member_id` or `Invoice.member_id`.** Both carry a database CHECK constraint, and rewriting an issued invoice's owner breaks the GST position. Linking writes `GuestRegistrant.linked_member_id` only.
- **Linking must never be able to fail a password set.** It runs after the `setInitialPassword` transaction commits, in a try/catch, and is recoverable by a backfill.
- **Do not modify any applied migration.** New migration files only (`docs/../CLAUDE.md`).
- **Do not run `git commit` without the user's explicit go-ahead.** Commit steps below are written out, but ask before running them.
- **Prisma commands:** `npm run prisma:migrate:create -- --name <name>` to author a migration, `npm run prisma:generate` after schema edits.
- **Test command:** `npm test` (vitest run) from `backend/`. Single file: `npx vitest run src/path/to/file.test.ts`.
- **Business rules are fixed by the spec (D-1…D-9). Do not invent new ones.** If something is unclear, stop and ask.

---

### Task 1: Schema, migration and the two switches

Everything downstream needs the columns, the enum values and the settings keys. Nothing behaves differently after this task — that is the point of doing it first and alone.

**Files:**
- Modify: `backend/prisma/schema/identity.prisma` (OtpPurpose enum)
- Modify: `backend/prisma/schema/event.prisma` (GuestRegistrant model)
- Create: `backend/prisma/migrations/<timestamp>_guest_booking_verification/migration.sql`
- Modify: `backend/src/helpers/settings.ts` (SETTING_KEYS)
- Modify: `backend/src/modules/settings/settings.types.ts` (EDITABLE_SETTINGS)
- Modify: `backend/prisma/seed/systemSettings.ts`
- Test: `backend/src/modules/settings/settings.flags.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `SETTING_KEYS.GUEST_BOOKING_OTP = 'events.guest_booking_otp'`
  - `SETTING_KEYS.BOOKING_LOOKUP_ENABLED = 'events.booking_lookup_enabled'`
  - `OtpPurpose.GUEST_BOOKING_VERIFY`, `OtpPurpose.BOOKING_LOOKUP`
  - `GuestRegistrant.email_verified_at: DateTime | null`
  - `GuestRegistrant.linked_member_id: bigint | null`

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/settings/settings.flags.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { EDITABLE_SETTINGS } from '@modules/settings/settings.types';
import { SETTING_KEYS } from '@helpers/settings';

describe('guest booking feature flags', () => {
  it('exposes both keys on SETTING_KEYS', () => {
    expect(SETTING_KEYS.GUEST_BOOKING_OTP).toBe('events.guest_booking_otp');
    expect(SETTING_KEYS.BOOKING_LOOKUP_ENABLED).toBe('events.booking_lookup_enabled');
  });

  it('makes both editable through the settings API', () => {
    expect(EDITABLE_SETTINGS['events.guest_booking_otp']).toBeDefined();
    expect(EDITABLE_SETTINGS['events.booking_lookup_enabled']).toBeDefined();
  });

  it('accepts only "true" or "false" for each', () => {
    for (const key of ['events.guest_booking_otp', 'events.booking_lookup_enabled']) {
      const rule = EDITABLE_SETTINGS[key]!;
      expect(rule.safeParse('true').success).toBe(true);
      expect(rule.safeParse('false').success).toBe(true);
      expect(rule.safeParse('yes').success).toBe(false);
      expect(rule.safeParse('').success).toBe(false);
    }
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd backend && npx vitest run src/modules/settings/settings.flags.test.ts`
Expected: FAIL — `SETTING_KEYS.GUEST_BOOKING_OTP` is undefined.

- [ ] **Step 3: Add the settings keys**

In `backend/src/helpers/settings.ts`, inside `SETTING_KEYS`, before the closing `} as const;`:

```ts
  /**
   * Require an OTP on the guest event booking company email.
   *
   * OFF (default) is exactly the behaviour that shipped before this existed: no
   * code is requested, none is required, and `email_verified_at` is never
   * written. It is a switch rather than a deploy so a problem with code delivery
   * is undone from the Settings screen in one click.
   */
  GUEST_BOOKING_OTP: 'events.guest_booking_otp',
  /** Serve `/my-bookings` and its two lookup endpoints. OFF (default) 404s them. */
  BOOKING_LOOKUP_ENABLED: 'events.booking_lookup_enabled',
```

- [ ] **Step 4: Make both editable**

In `backend/src/modules/settings/settings.types.ts`, inside `EDITABLE_SETTINGS`, alongside the other booleans:

```ts
  'events.guest_booking_otp': boolean,
  'events.booking_lookup_enabled': boolean,
```

- [ ] **Step 5: Run the test and confirm it passes**

Run: `cd backend && npx vitest run src/modules/settings/settings.flags.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 6: Edit the Prisma schema**

In `backend/prisma/schema/identity.prisma`, extend the enum:

```prisma
enum OtpPurpose {
  SIGNUP_VERIFY
  PASSWORD_RESET
  LOGIN_2FA
  /// Proves a guest owns the company email they typed on the event booking form.
  /// A separate purpose because the enum's own rule is that purpose is part of the
  /// lookup key — a signup code must not be replayable as a booking verification.
  GUEST_BOOKING_VERIFY
  /// Proves inbox ownership at `/my-bookings` read time. Distinct from
  /// GUEST_BOOKING_VERIFY so a code mailed for one cannot be used for the other.
  BOOKING_LOOKUP
}
```

In `backend/prisma/schema/event.prisma`, inside `model GuestRegistrant`, after `country`:

```prisma
  /// When the company email was proven by OTP (UTC). NULL means unproven — which is
  /// every row created before this existed, and every row booked while
  /// `events.guest_booking_otp` is off. Only a non-NULL row may be attached to a
  /// member account, because attaching an unproven address would let a stranger
  /// hang a booking, and its unpaid invoice, on a real company.
  email_verified_at DateTime? @db.Timestamptz(6)

  /// The member this guest booking was later recognised as (D-5, D-9). Set only from
  /// a verified email match. This is the WHOLE linking mechanism: the registration and
  /// invoice rows stay guest-owned, because both carry a CHECK requiring exactly one of
  /// member/guest, and an issued invoice must keep the party it was issued to.
  linked_member_id BigInt?

  linked_member Member? @relation(fields: [linked_member_id], references: [id], onDelete: SetNull, onUpdate: Cascade)
```

In `backend/prisma/schema/event.prisma`, in the `@@index` block of `GuestRegistrant`, add:

```prisma
  @@index([linked_member_id])
```

- [ ] **Step 7: Add the back-relation on Member**

In `backend/prisma/schema/member.prisma`, inside `model Member`, alongside the other relation lists:

```prisma
  linked_guest_registrants GuestRegistrant[]
```

- [ ] **Step 8: Generate the migration**

Run: `cd backend && npm run prisma:migrate:create -- --name guest_booking_verification`

Open the generated `migration.sql` and confirm it contains only `ALTER TYPE "OtpPurpose" ADD VALUE`, `ALTER TABLE "GuestRegistrants" ADD COLUMN` (both nullable), a foreign key and a `CREATE INDEX`. If it contains a `DROP`, a `NOT NULL`, or any `UPDATE`, stop and ask — the migration must be purely additive.

Add the column comments the repo requires (`npm run db:check-comments` enforces them):

```sql
COMMENT ON COLUMN "GuestRegistrants"."email_verified_at" IS 'When the company email was proven by OTP (UTC). NULL means unproven; only a proven row may be linked to a member.';
COMMENT ON COLUMN "GuestRegistrants"."linked_member_id" IS 'Member this guest booking was later recognised as. Visibility only - the registration and invoice rows stay guest-owned.';
```

- [ ] **Step 9: Apply it and regenerate the client**

Run: `cd backend && npm run prisma:migrate && npm run prisma:generate`
Then: `npm run db:check-comments`
Expected: migration applies, client regenerates, comment check passes.

- [ ] **Step 10: Seed both settings rows, default off**

In `backend/prisma/seed/systemSettings.ts`, following the shape of the `directory.enabled` row:

```ts
  {
    key: 'events.guest_booking_otp',
    value: 'false',
    value_type: 'BOOLEAN',
    group: 'events',
    /*
      Public, because the guest booking form has to know whether to render the
      verify step before anyone has typed anything. It leaks nothing: it says how
      the form behaves, which the form itself already shows.
    */
    is_public: true,
    description: 'Require an emailed code on the guest event booking company email.',
  },
  {
    key: 'events.booking_lookup_enabled',
    value: 'false',
    value_type: 'BOOLEAN',
    group: 'events',
    is_public: true,
    description: 'Serve the guest "find my bookings" page and its lookup endpoints.',
  },
```

- [ ] **Step 11: Run the seed and the full suite**

Run: `cd backend && npm run prisma:seed && npm test && npm run typecheck && npm run lint`
Expected: all pass. Nothing behaves differently yet — no code reads either flag.

- [ ] **Step 12: Commit** (ask the user first)

```bash
git add backend/prisma backend/src/helpers/settings.ts backend/src/modules/settings
git commit -m "feat(events): add guest booking verification columns and feature flags"
```

---

### Task 2: Booking OTP issue and consume

A small, self-contained module holding both OTP purposes. Kept out of `registration.service.ts`, which is already 1300 lines.

**Files:**
- Create: `backend/src/modules/event/booking.otp.ts`
- Create: `backend/src/modules/event/booking.otp.test.ts`
- Modify: `backend/prisma/seed/notificationTemplates.ts`

**Interfaces:**
- Consumes: `SETTING_KEYS` and the enum values from Task 1; `OTP` and `BCRYPT_COST` from `@constant/auth.constant`; `queueNotification` from `@notifications/outbox`.
- Produces:
  - `issueBookingOtp(db: Db, email: string, purpose: OtpPurpose): Promise<void>`
  - `consumeBookingOtp(db: Db, email: string, purpose: OtpPurpose, code: string): Promise<void>` — resolves on success, throws `AppError` on failure.
  - `BOOKING_OTP_TEMPLATE` / `LOOKUP_OTP_TEMPLATE` template code constants.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/booking.otp.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';
import bcrypt from 'bcryptjs';
import { OtpPurpose } from '@prisma/client';

vi.mock('@notifications/outbox', () => ({ queueNotification: vi.fn() }));

import { consumeBookingOtp, issueBookingOtp } from '@modules/event/booking.otp';
import { queueNotification } from '@notifications/outbox';

const live = (code: string, overrides: Record<string, unknown> = {}) => ({
  id: 1n,
  code_hash: bcrypt.hashSync(code, 4),
  expires_at: new Date(Date.now() + 600_000),
  attempt_count: 0,
  ...overrides,
});

const db = () => ({
  otpCode: {
    updateMany: vi.fn().mockResolvedValue({ count: 0 }),
    create: vi.fn().mockResolvedValue({ id: 1n }),
    findFirst: vi.fn(),
    update: vi.fn().mockResolvedValue({}),
  },
});

beforeEach(() => vi.clearAllMocks());

describe('issueBookingOtp', () => {
  it('retires any live code for the same email and purpose before issuing', async () => {
    const tx = db();
    await issueBookingOtp(tx as never, 'a@b.com', OtpPurpose.GUEST_BOOKING_VERIFY);

    expect(tx.otpCode.updateMany).toHaveBeenCalledOnce();
    expect(tx.otpCode.create).toHaveBeenCalledOnce();
    expect(queueNotification).toHaveBeenCalledOnce();
  });

  it('never puts the plaintext code in the stored row', async () => {
    const tx = db();
    await issueBookingOtp(tx as never, 'a@b.com', OtpPurpose.GUEST_BOOKING_VERIFY);

    const stored = tx.otpCode.create.mock.calls[0][0].data;
    const sent = (queueNotification as unknown as ReturnType<typeof vi.fn>).mock.calls[0][1]
      .payload.otp;

    expect(stored.code_hash).not.toBe(sent);
    expect(await bcrypt.compare(sent, stored.code_hash)).toBe(true);
  });
});

describe('consumeBookingOtp', () => {
  it('accepts the right code and consumes it', async () => {
    const tx = db();
    tx.otpCode.findFirst.mockResolvedValue(live('123456'));

    await expect(
      consumeBookingOtp(tx as never, 'a@b.com', OtpPurpose.GUEST_BOOKING_VERIFY, '123456'),
    ).resolves.toBeUndefined();

    expect(tx.otpCode.update).toHaveBeenCalledOnce();
  });

  it('rejects a wrong code and counts the attempt', async () => {
    const tx = db();
    tx.otpCode.findFirst.mockResolvedValue(live('123456'));

    await expect(
      consumeBookingOtp(tx as never, 'a@b.com', OtpPurpose.GUEST_BOOKING_VERIFY, '999999'),
    ).rejects.toThrow();

    expect(tx.otpCode.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { attempt_count: 1 } }),
    );
  });

  it('rejects when no code was ever issued', async () => {
    const tx = db();
    tx.otpCode.findFirst.mockResolvedValue(null);

    await expect(
      consumeBookingOtp(tx as never, 'a@b.com', OtpPurpose.GUEST_BOOKING_VERIFY, '123456'),
    ).rejects.toThrow();
  });

  it('rejects an expired code and retires it', async () => {
    const tx = db();
    tx.otpCode.findFirst.mockResolvedValue(
      live('123456', { expires_at: new Date(Date.now() - 1000) }),
    );

    await expect(
      consumeBookingOtp(tx as never, 'a@b.com', OtpPurpose.GUEST_BOOKING_VERIFY, '123456'),
    ).rejects.toThrow();

    expect(tx.otpCode.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ consumed_at: expect.any(Date) }) }),
    );
  });

  it('retires the code once the attempt ceiling is reached', async () => {
    const tx = db();
    tx.otpCode.findFirst.mockResolvedValue(live('123456', { attempt_count: 5 }));

    await expect(
      consumeBookingOtp(tx as never, 'a@b.com', OtpPurpose.GUEST_BOOKING_VERIFY, '123456'),
    ).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd backend && npx vitest run src/modules/event/booking.otp.test.ts`
Expected: FAIL — cannot resolve `@modules/event/booking.otp`.

- [ ] **Step 3: Write the module**

Create `backend/src/modules/event/booking.otp.ts`:

```ts
import bcrypt from 'bcryptjs';
import { NotificationChannel, OtpPurpose } from '@prisma/client';
import { BCRYPT_COST, OTP } from '@constant/auth.constant';
import { ERROR_TYPES } from '@constant/errorTypes.constant';
import type { Db } from '@db/prisma';
import { queueNotification } from '@notifications/outbox';
import { AppError } from '@utils/appError';

/**
 * Emailed codes for the two login-free event journeys: proving the company email
 * on a guest booking, and proving it again at `/my-bookings`.
 *
 * Deliberately a copy of the shape `auth.service.ts` uses for signup codes rather
 * than a shared abstraction over it. The two differ in what they are attached to —
 * a signup code hangs off a `Users` row that exists, these hang off an address that
 * may belong to nobody — and folding them together would put a member-account
 * concern inside a path that must never touch one.
 *
 * The plaintext code is generated, mailed and discarded. Only its bcrypt hash is
 * stored, for the same reason a password is: a six-digit code in a leaked table is
 * worth as much as the account it opens.
 */

export const BOOKING_OTP_TEMPLATE = 'event.booking_otp';
export const LOOKUP_OTP_TEMPLATE = 'event.booking_lookup_otp';

const TEMPLATE_FOR: Record<string, string> = {
  [OtpPurpose.GUEST_BOOKING_VERIFY]: BOOKING_OTP_TEMPLATE,
  [OtpPurpose.BOOKING_LOOKUP]: LOOKUP_OTP_TEMPLATE,
};

const invalidCode = (): AppError =>
  new AppError({ errorType: ERROR_TYPES.VALIDATION_ERROR, messageKey: 'auth.otpInvalid' });

/** Digits only, fixed length — a leading zero must survive, so it is a string throughout. */
const generateCode = (): string =>
  Array.from({ length: OTP.LENGTH }, () => Math.floor(Math.random() * 10)).join('');

/**
 * Issue a code and queue its email in the caller's transaction.
 *
 * Always inside a transaction, for the reason `issueSignupOtp` gives: a code with
 * no email leaves someone waiting for a message that never comes, and an email
 * with no code sends a number that will never verify.
 */
export const issueBookingOtp = async (
  db: Db,
  email: string,
  purpose: OtpPurpose,
): Promise<void> => {
  const code = generateCode();

  // Retire whatever is live first. The live-code index allows one per
  // (identifier, purpose), so a resend must supersede rather than collide.
  await db.otpCode.updateMany({
    where: { identifier: email, purpose, consumed_at: null },
    data: { consumed_at: new Date() },
  });

  await db.otpCode.create({
    data: {
      identifier: email,
      purpose,
      code_hash: await bcrypt.hash(code, BCRYPT_COST),
      expires_at: new Date(Date.now() + OTP.EXPIRY_MINUTES * 60_000),
    },
  });

  await queueNotification(db, {
    templateCode: TEMPLATE_FOR[purpose]!,
    channel: NotificationChannel.EMAIL,
    toAddress: email,
    payload: { otp: code, expiry_minutes: String(OTP.EXPIRY_MINUTES) },
  });
};

/**
 * Verify and consume a code, or throw.
 *
 * Every failure raises the same `auth.otpInvalid` except the attempt ceiling, which
 * says so plainly — the person needs to know a new code is required, and that fact
 * reveals nothing about whether the address exists.
 */
export const consumeBookingOtp = async (
  db: Db,
  email: string,
  purpose: OtpPurpose,
  code: string,
): Promise<void> => {
  const row = await db.otpCode.findFirst({
    where: { identifier: email, purpose, consumed_at: null },
    orderBy: { id: 'desc' },
  });

  if (!row) throw invalidCode();

  if (row.expires_at.getTime() <= Date.now()) {
    // Retire it, or the live-code index blocks the next resend.
    await db.otpCode.update({ where: { id: row.id }, data: { consumed_at: new Date() } });
    throw invalidCode();
  }

  if (row.attempt_count >= OTP.MAX_ATTEMPTS) {
    await db.otpCode.update({ where: { id: row.id }, data: { consumed_at: new Date() } });
    throw new AppError({
      errorType: ERROR_TYPES.VALIDATION_ERROR,
      messageKey: 'auth.otpMaxAttempts',
    });
  }

  if (!(await bcrypt.compare(code, row.code_hash))) {
    const attempts = row.attempt_count + 1;

    if (attempts >= OTP.MAX_ATTEMPTS) {
      await db.otpCode.update({ where: { id: row.id }, data: { consumed_at: new Date() } });
      throw new AppError({
        errorType: ERROR_TYPES.VALIDATION_ERROR,
        messageKey: 'auth.otpMaxAttempts',
      });
    }

    await db.otpCode.update({ where: { id: row.id }, data: { attempt_count: attempts } });
    throw invalidCode();
  }

  await db.otpCode.update({ where: { id: row.id }, data: { consumed_at: new Date() } });
};
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd backend && npx vitest run src/modules/event/booking.otp.test.ts`
Expected: PASS (7 tests).

- [ ] **Step 5: Seed the two email templates**

In `backend/prisma/seed/notificationTemplates.ts`, append to `TEMPLATES`:

```ts
  /* --- guest event booking: emailed codes --------------------------------
     Short, and they say what the code is for. A code with no context is the
     message people report as phishing. */
  {
    code: 'event.booking_otp',
    channel: NotificationChannel.EMAIL,
    locale: 'en',
    subject: 'Your booking verification code',
    body: [
      'Hello,',
      '',
      'Your code to confirm this email address for an event booking is:',
      '',
      '{{otp}}',
      '',
      'It expires in {{expiry_minutes}} minutes.',
      '',
      'If you did not start a booking, no action is needed — nothing has been',
      'booked and no invoice has been raised.',
    ].join('\n'),
  },
  {
    code: 'event.booking_lookup_otp',
    channel: NotificationChannel.EMAIL,
    locale: 'en',
    subject: 'Your code to view your bookings',
    body: [
      'Hello,',
      '',
      'Your code to view the bookings and invoices for this email address is:',
      '',
      '{{otp}}',
      '',
      'It expires in {{expiry_minutes}} minutes.',
      '',
      'If you did not ask for this, no action is needed — nobody can see anything',
      'without the code above.',
    ].join('\n'),
  },
```

- [ ] **Step 6: Re-seed and run the full suite**

Run: `cd backend && npm run prisma:seed && npm test && npm run typecheck && npm run lint`
Expected: all pass. Still nothing behaves differently — nothing calls this module yet.

- [ ] **Step 7: Commit** (ask the user first)

```bash
git add backend/src/modules/event/booking.otp.ts backend/src/modules/event/booking.otp.test.ts backend/prisma/seed/notificationTemplates.ts
git commit -m "feat(events): add booking OTP issue and consume with email templates"
```

---

### Task 3: Require the OTP on guest booking, behind the flag

The first task that changes behaviour — and only when the switch is on.

**Files:**
- Modify: `backend/src/modules/event/registration.types.ts` (`registerAsGuestSchema`, new `requestBookingOtpSchema`)
- Modify: `backend/src/modules/event/registration.service.ts` (`registerAsGuest`, new `requestBookingOtp`)
- Modify: `backend/src/modules/event/event.controller.ts`
- Modify: `backend/src/modules/event/event.routes.ts` (`eventPublicRouter`)
- Create: `backend/src/modules/event/registration.guestOtp.test.ts`

**Interfaces:**
- Consumes: `issueBookingOtp`, `consumeBookingOtp` (Task 2); `SETTING_KEYS.GUEST_BOOKING_OTP` (Task 1).
- Produces:
  - `POST /api/v1/public/events/booking/request-otp` — body `{ email }`, always 200.
  - `registerAsGuestSchema` with optional `otp_code`.
  - `GuestRegistrant.email_verified_at` written when the flag is on.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/registration.guestOtp.test.ts`. This tests the gate function in isolation — the full `registerAsGuest` transaction is covered by the existing suite and by the Self-Test Agent.

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { OtpPurpose } from '@prisma/client';

const getBooleanSetting = vi.fn();
vi.mock('@helpers/settings', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@helpers/settings')>()),
  getBooleanSetting,
}));

const consumeBookingOtp = vi.fn();
vi.mock('@modules/event/booking.otp', () => ({
  consumeBookingOtp,
  issueBookingOtp: vi.fn(),
  BOOKING_OTP_TEMPLATE: 'event.booking_otp',
  LOOKUP_OTP_TEMPLATE: 'event.booking_lookup_otp',
}));

import { verifyGuestEmail } from '@modules/event/registration.service';

beforeEach(() => vi.clearAllMocks());

describe('verifyGuestEmail', () => {
  it('does nothing at all when the flag is off — this is the "nothing broke" case', async () => {
    getBooleanSetting.mockResolvedValue(false);

    await expect(
      verifyGuestEmail({} as never, 'a@b.com', undefined),
    ).resolves.toBeNull();

    expect(consumeBookingOtp).not.toHaveBeenCalled();
  });

  it('ignores a code that was sent while the flag is off', async () => {
    getBooleanSetting.mockResolvedValue(false);

    await expect(verifyGuestEmail({} as never, 'a@b.com', '123456')).resolves.toBeNull();
    expect(consumeBookingOtp).not.toHaveBeenCalled();
  });

  it('refuses a booking with no code when the flag is on', async () => {
    getBooleanSetting.mockResolvedValue(true);

    await expect(verifyGuestEmail({} as never, 'a@b.com', undefined)).rejects.toThrow();
    expect(consumeBookingOtp).not.toHaveBeenCalled();
  });

  it('consumes the code and returns a verification instant when the flag is on', async () => {
    getBooleanSetting.mockResolvedValue(true);
    consumeBookingOtp.mockResolvedValue(undefined);

    const at = await verifyGuestEmail({} as never, 'a@b.com', '123456');

    expect(at).toBeInstanceOf(Date);
    expect(consumeBookingOtp).toHaveBeenCalledWith(
      expect.anything(),
      'a@b.com',
      OtpPurpose.GUEST_BOOKING_VERIFY,
      '123456',
    );
  });

  it('propagates a bad code as a failure, so the booking rolls back', async () => {
    getBooleanSetting.mockResolvedValue(true);
    consumeBookingOtp.mockRejectedValue(new Error('bad code'));

    await expect(verifyGuestEmail({} as never, 'a@b.com', '000000')).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd backend && npx vitest run src/modules/event/registration.guestOtp.test.ts`
Expected: FAIL — `verifyGuestEmail` is not exported.

- [ ] **Step 3: Add the optional field to the schema**

In `backend/src/modules/event/registration.types.ts`, inside `registerAsGuestSchema`, after `phone`:

```ts
  /*
    OPTIONAL here on purpose, and required in the service only when
    `events.guest_booking_otp` is on.

    A required field would reject every booking from a frontend that has not
    shipped the verify step yet, which would turn a backend deploy into an outage
    on a public form. The service is where the flag lives, so the service is where
    required-ness belongs.
  */
  otp_code: z.string().trim().regex(/^\d{6}$/).optional(),
```

And add, near `registerAsGuestSchema`:

```ts
/** Body of `POST /public/events/booking/request-otp`. */
export const requestBookingOtpSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(200),
});

export type RequestBookingOtpInput = z.infer<typeof requestBookingOtpSchema>;
```

- [ ] **Step 4: Add the gate and the request endpoint to the service**

In `backend/src/modules/event/registration.service.ts`, add the imports:

```ts
import { OtpPurpose } from '@prisma/client';
import { getBooleanSetting, SETTING_KEYS } from '@helpers/settings';
import { consumeBookingOtp, issueBookingOtp } from '@modules/event/booking.otp';
```

and these two exports:

```ts
/**
 * The email gate on a guest booking.
 *
 * Returns the instant the address was proven, or NULL when the feature is off.
 * NULL is not a failure — it is the pre-existing behaviour, and it is what keeps
 * `email_verified_at` empty so nothing written while the switch was off can ever
 * be auto-attached to a member account.
 *
 * Called INSIDE the booking transaction so the code is consumed with the booking:
 * a booking that rolls back for any later reason leaves the code live, and the
 * applicant is not told to request a new one for a booking that never happened.
 */
export const verifyGuestEmail = async (
  tx: Prisma.TransactionClient,
  email: string,
  code: string | undefined,
): Promise<Date | null> => {
  if (!(await getBooleanSetting(SETTING_KEYS.GUEST_BOOKING_OTP, false))) return null;

  if (!code) {
    throw new AppError({
      errorType: ERROR_TYPES.VALIDATION_ERROR,
      messageKey: 'auth.otpInvalid',
      details: { fields: { otp_code: 'auth.otpInvalid' } },
    });
  }

  await consumeBookingOtp(tx, email, OtpPurpose.GUEST_BOOKING_VERIFY, code);

  return new Date();
};

/**
 * Send a booking verification code.
 *
 * Answers the same way for every address, always. It says only that a code was
 * sent to something the caller typed, which is a fact they already knew — there is
 * nothing here to learn about who has booked before.
 */
export const requestBookingOtp = async (email: string): Promise<void> => {
  if (!(await getBooleanSetting(SETTING_KEYS.GUEST_BOOKING_OTP, false))) return;

  await prisma.$transaction(async (tx) => {
    await issueBookingOtp(tx, email, OtpPurpose.GUEST_BOOKING_VERIFY);
  });
};
```

- [ ] **Step 5: Call the gate inside `registerAsGuest`**

In `registerAsGuest`, inside `prisma.$transaction`, as the FIRST statement — before `seats.takeSeats`, so a failed verification never holds a seat:

```ts
    const emailVerifiedAt = await verifyGuestEmail(tx, input.email, input.otp_code);
```

Then in the `tx.guestRegistrant.create` call, add to `data`:

```ts
        email_verified_at: emailVerifiedAt,
```

- [ ] **Step 6: Add the controller**

In `backend/src/modules/event/event.controller.ts`:

```ts
export const requestBookingOtp = handler(async (req, res) => {
  await registrationService.requestBookingOtp(req.body.email);

  handleApiResponse(res, { responseType: RES_STATUS.ACTION, messageKey: 'auth.otpSent' });
});
```

Match the import name this file already uses for the registration service.

- [ ] **Step 7: Mount the route**

In `backend/src/modules/event/event.routes.ts`, in `eventPublicRouter`, immediately before the existing `booking/:token` GET (order matters — `request-otp` must not be read as a token):

```ts
eventPublicRouter.post(
  `${END_POINTS.EVENTS}/booking/request-otp`,
  rateLimiters.otp,
  validateRequest({ body: requestBookingOtpSchema }),
  controller.requestBookingOtp,
);
```

Import `rateLimiters` from `@middleware` and `requestBookingOtpSchema` from the types file if not already imported.

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `cd backend && npx vitest run src/modules/event/registration.guestOtp.test.ts && npm test`
Expected: the new file passes (5 tests) and the existing suite is unchanged.

- [ ] **Step 9: Verify the flag-off path by hand**

With `events.guest_booking_otp` still `false`, POST a guest booking with no `otp_code` through the existing form. It must succeed exactly as before, and the new `GuestRegistrants.email_verified_at` must be NULL.

Run: `cd backend && npm run typecheck && npm run lint`

- [ ] **Step 10: Commit** (ask the user first)

```bash
git add backend/src/modules/event
git commit -m "feat(events): gate guest booking on an emailed code behind events.guest_booking_otp"
```

---

### Task 4: Attach a verified booking to an existing member

D-5. Small, and it belongs with the booking write.

**Files:**
- Create: `backend/src/modules/event/booking.linking.ts`
- Create: `backend/src/modules/event/booking.linking.test.ts`
- Modify: `backend/src/modules/event/registration.service.ts` (`registerAsGuest`)

**Interfaces:**
- Consumes: `GuestRegistrant.linked_member_id` (Task 1); `verifyGuestEmail` (Task 3).
- Produces:
  - `memberIdForVerifiedEmail(db: Db, email: string): Promise<bigint | null>`
  - `linkVerifiedGuestBookings(db: Db, userId: bigint): Promise<number>` — used by Task 5 and the backfill.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/booking.linking.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { UserStatus } from '@prisma/client';

import {
  linkVerifiedGuestBookings,
  memberIdForVerifiedEmail,
} from '@modules/event/booking.linking';

const db = () => ({
  user: { findFirst: vi.fn() },
  member: { findFirst: vi.fn() },
  guestRegistrant: { updateMany: vi.fn().mockResolvedValue({ count: 0 }) },
});

beforeEach(() => vi.clearAllMocks());

describe('memberIdForVerifiedEmail', () => {
  it('returns the member id for an ACTIVE account with a member record', async () => {
    const tx = db();
    tx.user.findFirst.mockResolvedValue({ id: 7n, status: UserStatus.ACTIVE });
    tx.member.findFirst.mockResolvedValue({ id: 42n });

    await expect(memberIdForVerifiedEmail(tx as never, 'a@b.com')).resolves.toBe(42n);
  });

  it('returns null for a PENDING_APPROVAL applicant — they are not a member yet', async () => {
    const tx = db();
    tx.user.findFirst.mockResolvedValue(null); // the query filters on ACTIVE

    await expect(memberIdForVerifiedEmail(tx as never, 'a@b.com')).resolves.toBeNull();
    expect(tx.member.findFirst).not.toHaveBeenCalled();
  });

  it('returns null when the account has no member record', async () => {
    const tx = db();
    tx.user.findFirst.mockResolvedValue({ id: 7n, status: UserStatus.ACTIVE });
    tx.member.findFirst.mockResolvedValue(null);

    await expect(memberIdForVerifiedEmail(tx as never, 'a@b.com')).resolves.toBeNull();
  });
});

describe('linkVerifiedGuestBookings', () => {
  it('attaches only verified, unlinked rows for that exact email', async () => {
    const tx = db();
    tx.user.findFirst.mockResolvedValue({ id: 7n, email: 'a@b.com', status: UserStatus.ACTIVE });
    tx.member.findFirst.mockResolvedValue({ id: 42n });
    tx.guestRegistrant.updateMany.mockResolvedValue({ count: 2 });

    await expect(linkVerifiedGuestBookings(tx as never, 7n)).resolves.toBe(2);

    expect(tx.guestRegistrant.updateMany).toHaveBeenCalledWith({
      where: {
        email: 'a@b.com',
        email_verified_at: { not: null },
        linked_member_id: null,
      },
      data: { linked_member_id: 42n },
    });
  });

  it('is idempotent — a second run attaches nothing because the guard excludes linked rows', async () => {
    const tx = db();
    tx.user.findFirst.mockResolvedValue({ id: 7n, email: 'a@b.com', status: UserStatus.ACTIVE });
    tx.member.findFirst.mockResolvedValue({ id: 42n });
    tx.guestRegistrant.updateMany.mockResolvedValue({ count: 0 });

    await expect(linkVerifiedGuestBookings(tx as never, 7n)).resolves.toBe(0);
  });

  it('does nothing when the user owns no member record', async () => {
    const tx = db();
    tx.user.findFirst.mockResolvedValue({ id: 7n, email: 'a@b.com', status: UserStatus.ACTIVE });
    tx.member.findFirst.mockResolvedValue(null);

    await expect(linkVerifiedGuestBookings(tx as never, 7n)).resolves.toBe(0);
    expect(tx.guestRegistrant.updateMany).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd backend && npx vitest run src/modules/event/booking.linking.test.ts`
Expected: FAIL — cannot resolve `@modules/event/booking.linking`.

- [ ] **Step 3: Write the module**

Create `backend/src/modules/event/booking.linking.ts`:

```ts
import { UserStatus } from '@prisma/client';
import type { Db } from '@db/prisma';

/**
 * Recognising a guest booking as a member's, after the fact.
 *
 * The match key is a VERIFIED email and nothing else (D-4). Company name and GSTIN
 * are deliberately not consulted: a typo in either merges two different companies,
 * and unmerging afterwards means deciding which invoices belonged to whom.
 *
 * Nothing here rewrites ownership. `EventRegistration` and `Invoice` both carry a
 * CHECK requiring exactly one of member/guest, and an invoice already issued must
 * keep the party it names — so the only write is `GuestRegistrant.linked_member_id`,
 * which the member's read paths follow.
 */

/** The member behind an ACTIVE login with this address, if there is one. */
export const memberIdForVerifiedEmail = async (
  db: Db,
  email: string,
): Promise<bigint | null> => {
  const user = await db.user.findFirst({
    where: { email, status: UserStatus.ACTIVE, deletedAt: null },
    select: { id: true },
  });

  if (!user) return null;

  const member = await db.member.findFirst({
    where: { primary_user_id: user.id, deletedAt: null },
    select: { id: true },
  });

  return member?.id ?? null;
};

/**
 * Attach every verified, unattached guest booking made with this user's address.
 *
 * Returns how many rows were attached. Idempotent: `linked_member_id: null` in the
 * filter means a second run over the same member writes nothing, which is what lets
 * the backfill be run as often as anyone likes.
 *
 * `email_verified_at: { not: null }` is the security boundary. Rows written before
 * this feature existed, and rows written while the switch was off, have NULL there
 * and are never attached — their addresses were never proven, and attaching one
 * would hang a stranger's booking, and its unpaid invoice, on a real company.
 */
export const linkVerifiedGuestBookings = async (db: Db, userId: bigint): Promise<number> => {
  const user = await db.user.findFirst({
    where: { id: userId, deletedAt: null },
    select: { email: true },
  });

  if (!user) return 0;

  const member = await db.member.findFirst({
    where: { primary_user_id: userId, deletedAt: null },
    select: { id: true },
  });

  if (!member) return 0;

  const { count } = await db.guestRegistrant.updateMany({
    where: {
      email: user.email,
      email_verified_at: { not: null },
      linked_member_id: null,
    },
    data: { linked_member_id: member.id },
  });

  return count;
};
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd backend && npx vitest run src/modules/event/booking.linking.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 5: Attach at booking time**

In `registerAsGuest` in `registration.service.ts`, after `verifyGuestEmail` and before the guest is created:

```ts
    /*
      An address we have just proven, belonging to a member who chose not to sign in.

      Attached now so the booking is not orphaned. The PRICE is untouched: they were
      offered the member rate behind "Sign in for the member price" and did not take
      it, and re-pricing after the fact would mean re-issuing an invoice (D-7). The
      form is not told the address is known, either — that would turn it into a way
      to discover which addresses have accounts.
    */
    const linkedMemberId = emailVerifiedAt
      ? await memberIdForVerifiedEmail(tx, input.email)
      : null;
```

and in `tx.guestRegistrant.create`'s `data`:

```ts
        linked_member_id: linkedMemberId,
```

Import `memberIdForVerifiedEmail` from `@modules/event/booking.linking`.

- [ ] **Step 6: Run the full suite**

Run: `cd backend && npm test && npm run typecheck && npm run lint`
Expected: all pass. With the flag off, `emailVerifiedAt` is NULL, so the lookup never runs.

- [ ] **Step 7: Commit** (ask the user first)

```bash
git add backend/src/modules/event
git commit -m "feat(events): attach a verified guest booking to an existing member"
```

---

### Task 5: Link at first sign-in, without risking the password

D-9. The one change to the auth module.

**Files:**
- Modify: `backend/src/modules/auth/auth.service.ts` (`setInitialPassword`)
- Create: `backend/src/modules/auth/setInitialPassword.linking.test.ts`

**Interfaces:**
- Consumes: `linkVerifiedGuestBookings` (Task 4).
- Produces: nothing new. `setInitialPassword`'s signature and return type are unchanged.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/auth/setInitialPassword.linking.test.ts`:

```ts
import { describe, expect, it, vi, beforeEach } from 'vitest';

const linkVerifiedGuestBookings = vi.fn();
vi.mock('@modules/event/booking.linking', () => ({
  linkVerifiedGuestBookings,
  memberIdForVerifiedEmail: vi.fn(),
}));

const loggerError = vi.fn();
vi.mock('@logger/logger', () => ({
  logger: { info: vi.fn(), warn: vi.fn(), error: loggerError, debug: vi.fn() },
}));

import { attachBookingsAfterActivation } from '@modules/auth/auth.service';

beforeEach(() => vi.clearAllMocks());

describe('attachBookingsAfterActivation', () => {
  it('attaches bookings for the newly active member', async () => {
    linkVerifiedGuestBookings.mockResolvedValue(3);

    await expect(attachBookingsAfterActivation(7n)).resolves.toBeUndefined();

    expect(linkVerifiedGuestBookings).toHaveBeenCalledWith(expect.anything(), 7n);
  });

  it('swallows a failure — the password is already set and must stand', async () => {
    linkVerifiedGuestBookings.mockRejectedValue(new Error('database is on fire'));

    await expect(attachBookingsAfterActivation(7n)).resolves.toBeUndefined();

    expect(loggerError).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd backend && npx vitest run src/modules/auth/setInitialPassword.linking.test.ts`
Expected: FAIL — `attachBookingsAfterActivation` is not exported.

- [ ] **Step 3: Add the best-effort wrapper**

In `backend/src/modules/auth/auth.service.ts`, add the import:

```ts
import { linkVerifiedGuestBookings } from '@modules/event/booking.linking';
```

and, immediately above `setInitialPassword`:

```ts
/**
 * Attach any event bookings this member made as a guest, after their account is live.
 *
 * OUTSIDE the password transaction, and it cannot throw.
 *
 * Inside it, a failure here would roll back the password and lock the member out of
 * the account they were just given — to save them from missing rows on a list. The
 * trade is the one `activation.service.ts` already makes for document copying: the
 * thing that must be atomic is atomic, and the recoverable thing is allowed to fail
 * and be re-run. `scripts/backfill-guest-booking-links.ts` is the re-run.
 */
export const attachBookingsAfterActivation = async (userId: bigint): Promise<void> => {
  try {
    const linked = await linkVerifiedGuestBookings(prisma, userId);

    if (linked > 0) {
      logger.info('events.guestBookingsLinked', { userId: userId.toString(), linked });
    }
  } catch (error) {
    logger.error('events.guestBookingLinkFailed', {
      userId: userId.toString(),
      error: error instanceof Error ? error.message : String(error),
    });
  }
};
```

- [ ] **Step 4: Call it after the transaction**

In `setInitialPassword`, after the closing `});` of `prisma.$transaction` and before the function ends:

```ts
  await attachBookingsAfterActivation(user.id);
```

Leave the transaction body exactly as it is. Do not move the call inside it.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `cd backend && npx vitest run src/modules/auth/setInitialPassword.linking.test.ts && npm test`
Expected: the new file passes (2 tests) and the existing auth suite is unchanged.

Run: `npm run typecheck && npm run lint`

- [ ] **Step 6: Commit** (ask the user first)

```bash
git add backend/src/modules/auth
git commit -m "feat(auth): attach verified guest bookings after a member sets their first password"
```

---

### Task 6: Backfill script

**Files:**
- Create: `backend/scripts/backfill-guest-booking-links.ts`
- Modify: `backend/package.json` (scripts)

**Interfaces:**
- Consumes: `linkVerifiedGuestBookings` (Task 4).
- Produces: `npm run backfill:guest-booking-links [-- --dry-run]`

- [ ] **Step 1: Write the script**

Create `backend/scripts/backfill-guest-booking-links.ts`, following `backfill-member-documents.ts`:

```ts
/**
 * Attach verified guest event bookings to the members who made them.
 *
 * Covers two backlogs: members activated before the linking step existed, and
 * members whose linking failed at set-password time — where the failure is
 * deliberately swallowed so it cannot undo a password (see
 * `attachBookingsAfterActivation`).
 *
 * Safe to re-run. `linkVerifiedGuestBookings` filters on `linked_member_id IS NULL`,
 * so a second pass over the same member writes nothing.
 *
 * It will NOT attach a booking whose `email_verified_at` is NULL, which is every
 * booking made before the OTP existed. That is the point, not an oversight — those
 * addresses were never proven, and attaching one could hang a stranger's unpaid
 * invoice on a real company.
 *
 *   npx tsx scripts/backfill-guest-booking-links.ts [--dry-run]
 */
import { PrismaClient, UserStatus } from '@prisma/client';
import { linkVerifiedGuestBookings } from '../src/modules/event/booking.linking';

const prisma = new PrismaClient();
const dryRun = process.argv.includes('--dry-run');

const main = async (): Promise<void> => {
  const candidates = await prisma.user.findMany({
    where: {
      status: UserStatus.ACTIVE,
      deletedAt: null,
      // `Members.primary_user_id` is @unique, so this relation is a to-one.
      member: { isNot: null },
    },
    select: { id: true, email: true },
    orderBy: { id: 'asc' },
  });

  console.log(`${candidates.length} active member login(s) to check${dryRun ? ' (dry run)' : ''}`);

  let linked = 0;
  let touched = 0;

  for (const user of candidates) {
    if (dryRun) {
      const pending = await prisma.guestRegistrant.count({
        where: { email: user.email, email_verified_at: { not: null }, linked_member_id: null },
      });

      if (pending > 0) {
        console.log(`  would link ${pending} booking(s) for user ${user.id}`);
        linked += pending;
        touched += 1;
      }

      continue;
    }

    const count = await linkVerifiedGuestBookings(prisma, user.id);

    if (count > 0) {
      console.log(`  linked ${count} booking(s) for user ${user.id}`);
      linked += count;
      touched += 1;
    }
  }

  console.log(`${linked} booking(s) across ${touched} member(s)`);
};

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => void prisma.$disconnect());
```

The relation is `User.member` (singular — `Members.primary_user_id` is `@unique`), so `member: { isNot: null }` is the correct filter, not `some`.

- [ ] **Step 2: Add the npm script**

In `backend/package.json`, beside the other backfills:

```json
    "backfill:guest-booking-links": "tsx scripts/backfill-guest-booking-links.ts",
```

- [ ] **Step 3: Run it dry against the dev database**

Run: `cd backend && npm run backfill:guest-booking-links -- --dry-run`
Expected: it lists 0 bookings, because no verified rows exist yet. That is the correct answer today, and proves the guard works.

Run: `npm run typecheck && npm run lint`

- [ ] **Step 4: Commit** (ask the user first)

```bash
git add backend/scripts/backfill-guest-booking-links.ts backend/package.json
git commit -m "chore(events): add guest booking link backfill"
```

---

### Task 7: Show linked bookings and invoices on the member's own screens

**Files:**
- Modify: `backend/src/modules/event/registration.service.ts` (`listMyBookings`)
- Modify: `backend/src/modules/member/member.repository.ts` (`listOwnInvoices`, `ownInvoiceYears`)
- Modify: `backend/src/modules/member/member.service.ts` (`listOwnInvoices` row mapping)
- Create: `backend/src/modules/event/booking.linkedVisibility.test.ts`
- Modify: `customer/src/components/events/MyBookings.tsx`
- Modify: `customer/src/app/(member)/invoices/` (the invoices list component)
- Modify: `customer/src/services/EventService.ts` and `MemberService.ts` (row types)

**Interfaces:**
- Consumes: `GuestRegistrant.linked_member_id` (Task 1).
- Produces: every booking row and invoice row gains `booked_as_guest: boolean`, rendered as a "Booked before membership" badge in the customer app.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/booking.linkedVisibility.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { bookingsWhereForMember, invoicesWhereForMember } from '@modules/event/booking.linking';

describe('bookingsWhereForMember', () => {
  it('matches the member\'s own bookings and the guest bookings linked to them', () => {
    expect(bookingsWhereForMember(42n)).toEqual({
      deletedAt: null,
      OR: [{ member_id: 42n }, { guest_registrant: { linked_member_id: 42n } }],
    });
  });
});

describe('invoicesWhereForMember', () => {
  it('matches the member\'s own invoices and the guest invoices linked to them', () => {
    expect(invoicesWhereForMember(42n)).toEqual({
      deletedAt: null,
      OR: [{ member_id: 42n }, { guest_registrant: { linked_member_id: 42n } }],
    });
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd backend && npx vitest run src/modules/event/booking.linkedVisibility.test.ts`
Expected: FAIL — the two helpers are not exported.

- [ ] **Step 3: Add the two filter builders**

Append to `backend/src/modules/event/booking.linking.ts`:

```ts
/**
 * What "mine" means on a member's own screens, once guest history can be linked.
 *
 * Built here, once, rather than written out at each call site: bookings and invoices
 * must agree about what belongs to a member, and two hand-written filters drift.
 *
 * The linked half reaches rows the member does NOT own — the CHECK constraint keeps
 * them guest-owned forever. This is a visibility join, and every read path that uses
 * it must treat those rows as read-only history.
 */
export const bookingsWhereForMember = (memberId: bigint) => ({
  deletedAt: null,
  OR: [{ member_id: memberId }, { guest_registrant: { linked_member_id: memberId } }],
});

export const invoicesWhereForMember = (memberId: bigint) => ({
  deletedAt: null,
  OR: [{ member_id: memberId }, { guest_registrant: { linked_member_id: memberId } }],
});
```

- [ ] **Step 4: Use them in the two read paths**

In `listMyBookings` in `registration.service.ts`, replace
`where: { member_id: memberId, deletedAt: null }` with `where: bookingsWhereForMember(memberId)`,
add `guest_registrant: { select: { id: true } }` to the `include`, and set on each mapped row:

```ts
      /* Booked before this company was a member. The row is still guest-owned — it is
         shown here, never re-billed (D-7) — so the UI can say so rather than implying
         the invoice was raised to the member. */
      booked_as_guest: booking.member_id === null,
```

In `member.repository.ts`'s `listOwnInvoices` and `ownInvoiceYears`, replace the
`member_id: memberId` filter with `invoicesWhereForMember(memberId)`, and in
`member.service.ts` add to the mapped row:

```ts
      booked_as_guest: row.member_id === null,
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `cd backend && npx vitest run src/modules/event/booking.linkedVisibility.test.ts && npm test`
Expected: the new file passes (2 tests) and the existing suites are unchanged — with no linked rows in the database, both queries return exactly what they returned before.

Run: `npm run typecheck && npm run lint`

- [ ] **Step 6: Label the linked rows in the customer app**

Add `booked_as_guest: boolean` to the booking row type in `EventService.ts` and the
invoice row type in `MemberService.ts`, then render a quiet badge on rows where it is
true — in `MyBookings.tsx` and in the member invoices list.

Wording: **"Booked before membership"**. Flagged in the spec as a placeholder, not
approved copy — if the client has not confirmed it by the time you reach this step,
use it and raise it, do not invent an alternative.

Why the badge exists at all: without it the screen implies the invoice was raised to
the member's company, and it was not — it names the guest party it was issued to, and
it is deliberately never re-addressed (D-7). Somebody reconciling GST needs to be able
to see which is which without opening the PDF.

- [ ] **Step 7: Verify in the browser**

Run: `cd customer && npm run lint && npx tsc --noEmit`

With no linked rows, both screens must render exactly as they do today — no badge, no
empty space where one would go.

- [ ] **Step 8: Commit** (ask the user first)

```bash
git add backend/src/modules/event backend/src/modules/member customer/src
git commit -m "feat(members): surface linked guest bookings and invoices on member screens"
```

---

### Task 8: The guest lookup endpoints

**Files:**
- Create: `backend/src/modules/event/booking.lookup.tokens.ts`
- Create: `backend/src/modules/event/booking.lookup.tokens.test.ts`
- Create: `backend/src/modules/event/booking.lookup.service.ts`
- Modify: `backend/src/modules/event/registration.types.ts` (two schemas)
- Modify: `backend/src/modules/event/event.controller.ts`
- Modify: `backend/src/modules/event/event.routes.ts`

**Interfaces:**
- Consumes: `issueBookingOtp` / `consumeBookingOtp` (Task 2); `SETTING_KEYS.BOOKING_LOOKUP_ENABLED` (Task 1).
- Produces:
  - `signBookingLookupToken(email: string): string`
  - `verifyBookingLookupToken(token: string): string` — returns the email, throws `AppError` otherwise.
  - `POST /api/v1/public/events/bookings/lookup/request-otp`
  - `POST /api/v1/public/events/bookings/lookup`
  - `GET  /api/v1/public/events/bookings/lookup/invoice/:invoiceId/pdf`

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/event/booking.lookup.tokens.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import {
  signBookingLookupToken,
  verifyBookingLookupToken,
} from '@modules/event/booking.lookup.tokens';

describe('booking lookup token', () => {
  it('round-trips the email it was issued for', () => {
    const token = signBookingLookupToken('a@b.com');
    expect(verifyBookingLookupToken(token)).toBe('a@b.com');
  });

  it('refuses a token that is not one of ours', () => {
    expect(() => verifyBookingLookupToken('not.a.token')).toThrow();
  });

  it('refuses a member access token — the scopes must not be interchangeable', async () => {
    const { signMemberAccessToken } = await import('@utils/jwt');
    const memberToken = signMemberAccessToken({ userId: 1n, status: 'ACTIVE' as never });

    expect(() => verifyBookingLookupToken(memberToken)).toThrow();
  });
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd backend && npx vitest run src/modules/event/booking.lookup.tokens.test.ts`
Expected: FAIL — cannot resolve the module.

- [ ] **Step 3: Write the token module**

Create `backend/src/modules/event/booking.lookup.tokens.ts`:

```ts
import jwt from 'jsonwebtoken';
import { environment } from '@config/config';
import { ERROR_TYPES } from '@constant/errorTypes.constant';
import { AppError } from '@utils/appError';

/**
 * A 30-minute pass to read one email address's bookings (D-6).
 *
 * A signed JWT rather than a stored opaque token: it expires before anyone could
 * act on a revocation, so a table and a migration would buy nothing.
 *
 * Kept out of `utils/jwt.ts` on purpose. Everything there is an AUDIENCE token, and
 * `authenticate` accepts those. This must never satisfy `authenticate` — it proves
 * only that somebody read one inbox, which is nothing like being signed in. The
 * explicit `scope` claim, checked on the way back in, is what keeps a member token
 * from working here and this from working anywhere else.
 */

const SCOPE = 'booking_lookup';
const TTL_SECONDS = 30 * 60;

interface LookupClaims {
  scope: string;
  email: string;
}

export const signBookingLookupToken = (email: string): string =>
  jwt.sign({ scope: SCOPE, email }, environment.jwtSecret, { expiresIn: TTL_SECONDS });

export const verifyBookingLookupToken = (token: string): string => {
  const invalid = (): AppError =>
    new AppError({ errorType: ERROR_TYPES.UNAUTHORIZED, messageKey: 'auth.invalidToken' });

  let claims: LookupClaims;

  try {
    claims = jwt.verify(token, environment.jwtSecret) as LookupClaims;
  } catch {
    throw invalid();
  }

  if (claims.scope !== SCOPE || typeof claims.email !== 'string' || !claims.email) {
    throw invalid();
  }

  return claims.email;
};
```

Use whatever `environment` actually calls the JWT secret — read `backend/src/utils/jwt.ts` and match it exactly.

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd backend && npx vitest run src/modules/event/booking.lookup.tokens.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Add the two schemas**

In `registration.types.ts`:

```ts
/** Body of `POST /public/events/bookings/lookup/request-otp`. */
export const requestLookupOtpSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(200),
});

/** Body of `POST /public/events/bookings/lookup`. */
export const bookingLookupSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(200),
  otp_code: z.string().trim().regex(/^\d{6}$/),
});

export type RequestLookupOtpInput = z.infer<typeof requestLookupOtpSchema>;
export type BookingLookupInput = z.infer<typeof bookingLookupSchema>;
```

- [ ] **Step 6: Write the service**

Create `backend/src/modules/event/booking.lookup.service.ts`:

```ts
import { OtpPurpose } from '@prisma/client';
import { ERROR_TYPES } from '@constant/errorTypes.constant';
import { prisma } from '@db/prisma';
import { getBooleanSetting, SETTING_KEYS } from '@helpers/settings';
import { consumeBookingOtp, issueBookingOtp } from '@modules/event/booking.otp';
import { signBookingLookupToken } from '@modules/event/booking.lookup.tokens';
import { AppError } from '@utils/appError';

/**
 * "Find my bookings" — every booking made with one email address (D-3).
 *
 * The OTP taken here is the whole of the authorisation, and it is taken NOW. That is
 * why this returns rows whose `email_verified_at` is NULL, including everything
 * booked before the OTP existed: proving the inbox at read time is proof enough to
 * read. Verification at BOOKING time is a stricter bar because it authorises an
 * unattended, durable write — attaching a booking to a member account.
 */

const notFound = (): AppError =>
  new AppError({ errorType: ERROR_TYPES.NOT_FOUND, messageKey: 'common.notFound' });

/** 404 rather than 403 when the feature is off: an unbuilt page and a disabled one look alike. */
export const assertLookupEnabled = async (): Promise<void> => {
  if (!(await getBooleanSetting(SETTING_KEYS.BOOKING_LOOKUP_ENABLED, false))) throw notFound();
};

export const requestLookupOtp = async (email: string): Promise<void> => {
  await assertLookupEnabled();

  await prisma.$transaction(async (tx) => {
    await issueBookingOtp(tx, email, OtpPurpose.BOOKING_LOOKUP);
  });
};

export const lookupBookings = async (email: string, code: string) => {
  await assertLookupEnabled();

  await prisma.$transaction(async (tx) => {
    await consumeBookingOtp(tx, email, OtpPurpose.BOOKING_LOOKUP, code);
  });

  const registrations = await prisma.eventRegistration.findMany({
    where: { guest_registrant: { email }, deletedAt: null },
    orderBy: { registered_at: 'desc' },
    include: {
      event: { select: { title: true, slug: true, start_at: true, venue_name: true, city: true } },
      attendees: { orderBy: { id: 'asc' }, select: { attendee_code: true, full_name: true } },
      invoice: {
        select: {
          id: true,
          invoice_number: true,
          status: true,
          total_amount: true,
          due_date: true,
        },
      },
    },
  });

  return {
    /*
      Issued only after the code is consumed, so it cannot be obtained by guessing.
      It carries the email and nothing else — every read behind it re-derives what is
      visible from that address rather than trusting an id in a path.
    */
    lookup_token: signBookingLookupToken(email),
    bookings: registrations.map((row) => ({
      id: row.id.toString(),
      registration_code: row.registration_code,
      status: row.status,
      attendee_count: row.attendee_count,
      total_amount: row.total_amount.toFixed(2),
      registered_at: row.registered_at,
      event: row.event,
      attendees: row.attendees,
      invoice: row.invoice
        ? {
            id: row.invoice.id.toString(),
            invoice_number: row.invoice.invoice_number,
            status: row.invoice.status,
            total_amount: row.invoice.total_amount.toFixed(2),
            due_date: row.invoice.due_date,
          }
        : null,
    })),
  };
};

```

Invoice authorisation is deliberately NOT written here — see Step 7a.

- [ ] **Step 7a: Teach `getInvoicePdf` about a guest viewer**

`member.service.ts`'s `getInvoicePdf` already owns the question "may this caller see
this invoice", and its guard is `viewer.memberId === invoice.member_id`. A guest
invoice has `member_id = NULL`, so a guest can never satisfy it — and passing
`isAdmin: true` to get around that would hand the caller **every invoice in the
system**. Extend the viewer instead, so the rule stays in one place:

```ts
export const getInvoicePdf = async (
  invoiceId: bigint,
  viewer: { memberId: bigint | null; isAdmin: boolean; guestEmail?: string | null },
) => {
```

and replace the ownership line with:

```ts
  const isOwner = viewer.memberId !== null && viewer.memberId === invoice.member_id;
  /*
    A guest proved this address by OTP minutes ago (D-3, D-6). They own this invoice
    in every sense that matters: it names them, and it is the only copy they have.
    Matched against the invoice's OWN guest row rather than an id from the path, so a
    valid lookup token cannot be pointed at somebody else's invoice.
  */
  const isGuestOwner =
    !!viewer.guestEmail && invoice.guest_registrant?.email === viewer.guestEmail;

  if (!isOwner && !isGuestOwner && !viewer.isAdmin) throw notFound('member.invoiceNotFound');
```

`guest_registrant` is already in that function's `include`, so nothing else changes.
Existing callers pass no `guestEmail` and are unaffected.

- [ ] **Step 7b: Add the controllers**

In `event.controller.ts`:

```ts
export const requestLookupOtp = handler(async (req, res) => {
  await lookupService.requestLookupOtp(req.body.email);

  handleApiResponse(res, { responseType: RES_STATUS.ACTION, messageKey: 'auth.otpSent' });
});

export const lookupBookings = handler(async (req, res) => {
  const result = await lookupService.lookupBookings(req.body.email, req.body.otp_code);

  handleApiResponse(res, { responseType: RES_STATUS.FETCH, data: result });
});

export const downloadLookupInvoicePdf = handler(async (req, res) => {
  await lookupService.assertLookupEnabled();

  const email = verifyBookingLookupToken(bearerToken(req.get('authorization')) ?? '');

  const file = await memberService.getInvoicePdf(BigInt(req.params.invoiceId as string), {
    memberId: null,
    isAdmin: false,
    guestEmail: email,
  });

  streamPdf(res, file);
});
```

`isAdmin: false` matters — the guest is authorised by `guestEmail` alone, through the
guard added in Step 7a. Import `streamPdf` and `memberService` the same way
`member.controller.ts` does. Export `assertEnabled` from the lookup service as
`assertLookupEnabled` so this route 404s with the flag off like the other two.

- [ ] **Step 8: Mount the routes**

In `event.routes.ts`, in `eventPublicRouter`, BEFORE the `booking/:token` route:

```ts
eventPublicRouter.post(
  `${END_POINTS.EVENTS}/bookings/lookup/request-otp`,
  rateLimiters.otp,
  validateRequest({ body: requestLookupOtpSchema }),
  controller.requestLookupOtp,
);

eventPublicRouter.post(
  `${END_POINTS.EVENTS}/bookings/lookup`,
  rateLimiters.otp,
  validateRequest({ body: bookingLookupSchema }),
  controller.lookupBookings,
);

eventPublicRouter.get(
  `${END_POINTS.EVENTS}/bookings/lookup/invoice/:invoiceId/pdf`,
  controller.downloadLookupInvoicePdf,
);
```

- [ ] **Step 9: Verify both flag states by hand**

With `events.booking_lookup_enabled` still `false`:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8000/api/v1/public/events/bookings/lookup/request-otp \
  -H 'content-type: application/json' -d '{"email":"a@b.com"}'
```

Expected: `404`. Then set the flag true in the database, repeat, expect `200`, and set it back to false.

Run: `cd backend && npm test && npm run typecheck && npm run lint`

- [ ] **Step 10: Commit** (ask the user first)

```bash
git add backend/src/modules/event
git commit -m "feat(events): add OTP-gated guest booking lookup and invoice download"
```

---

### Task 9: Customer — the verify step on the guest booking form

**Files:**
- Modify: `customer/src/constants/endpoints.ts`
- Modify: `customer/src/services/EventService.ts`
- Modify: `customer/src/components/events/GuestRegisterView.tsx`

**Interfaces:**
- Consumes: `POST /public/events/booking/request-otp` (Task 3); the public setting `events.guest_booking_otp` from `GET /public/settings`.
- Produces: `otp_code` on the guest register payload.

- [ ] **Step 1: Add the endpoints**

In `customer/src/constants/endpoints.ts`, beside the existing guest booking entries:

```ts
  /** Emailed code proving the company email on a guest booking. */
  guestBookingRequestOtp: '/public/events/booking/request-otp',
  bookingLookupRequestOtp: '/public/events/bookings/lookup/request-otp',
  bookingLookup: '/public/events/bookings/lookup',
  bookingLookupInvoicePdf: (id: string) =>
    `/public/events/bookings/lookup/invoice/${id}/pdf`,
```

- [ ] **Step 2: Add the service call**

In `customer/src/services/EventService.ts`:

```ts
  /** Ask for a code on the company email. Answers the same way for every address. */
  async requestBookingOtp(email: string): Promise<void> {
    await ApiService.post<unknown>(ENDPOINTS.guestBookingRequestOtp, { email });
  },
```

Match the object/class style the rest of the file uses.

- [ ] **Step 3: Read the flag and render the verify step**

In `GuestRegisterView.tsx`:

- read `events.guest_booking_otp` from the public settings the app already fetches (`SiteService` / `publicSettings`); when it is not `'true'`, render exactly what renders today and send no `otp_code`;
- when it is `'true'`, add beside Company Email a **Send code** button calling `EventService.requestBookingOtp(form.email)`, and a six-digit code field below it;
- block submit with a message when the flag is on and the code field is empty — the existing `setError` pattern in `validate()`;
- include `otp_code: form.otp_code.trim()` in the payload built at the `full_name: form.company_name.trim()` call site, and omit the key entirely when the flag is off.

Explain in a comment why the field is omitted rather than sent empty: the server treats absent and empty differently only when the flag is on, and sending an empty string from a build where the flag is off would start failing the moment somebody flips the switch.

- [ ] **Step 4: Verify both flag states in the browser**

With the flag off: the form looks and behaves exactly as it does today. Book an event end to end.
With the flag on: the code field appears, a wrong code is refused, the right one books.
Then set it back to off.

Run: `cd customer && npm run lint && npx tsc --noEmit`

- [ ] **Step 5: Commit** (ask the user first)

```bash
git add customer/src/constants/endpoints.ts customer/src/services/EventService.ts customer/src/components/events/GuestRegisterView.tsx
git commit -m "feat(events): add the company email verify step to the guest booking form"
```

---

### Task 10: Customer — the `/my-bookings` page

**Files:**
- Create: `customer/src/app/(public)/my-bookings/page.tsx`
- Create: `customer/src/components/events/FindMyBookings.tsx`
- Modify: `customer/src/services/EventService.ts`
- Modify: `customer/src/constants/routes.ts`

**Interfaces:**
- Consumes: the two lookup endpoints and the invoice PDF route (Task 8).
- Produces: the public route `/my-bookings`.

- [ ] **Step 1: Add the service calls**

In `EventService.ts`:

```ts
  async requestBookingLookupOtp(email: string): Promise<void> {
    await ApiService.post<unknown>(ENDPOINTS.bookingLookupRequestOtp, { email });
  },

  async lookupBookings(email: string, otpCode: string): Promise<BookingLookupResult> {
    const envelope = await ApiService.post<unknown>(ENDPOINTS.bookingLookup, {
      email,
      otp_code: otpCode,
    });

    return unwrap<BookingLookupResult>(envelope);
  },
```

Define `BookingLookupResult` in the same file's types section, mirroring the service response from Task 8: `{ lookup_token: string; bookings: BookingLookupRow[] }`.

Use whatever unwrapping helper this file already uses for envelopes — copy it from a neighbouring method rather than inventing one.

- [ ] **Step 2: Build the component**

Create `FindMyBookings.tsx` as a two-step client component:

- **Step one** — email field, "Email me a code". Always show the same confirmation, whatever the address. Never say whether it was found.
- **Step two** — six-digit code field, then the list.
- **The list** — one card per booking: event title, date, venue, registration code, status, amount, attendee codes, and an invoice download when there is one.
- **Empty result** — "No bookings found for that email address." Not an error state, and no suggestion that a different address might work.
- Hold `lookup_token` in component state only. **Do not put it in `localStorage`, Redux, or the URL** — it is a 30-minute credential, and this page may be opened on a shared machine, which is the reason the expiry is short in the first place.
- Download the invoice by fetching `ENDPOINTS.bookingLookupInvoicePdf(id)` with `Authorization: Bearer <lookup_token>` and turning the response into an object URL.

- [ ] **Step 3: Add the page and the route constant**

`page.tsx`:

```tsx
import type { Metadata } from 'next';

import FindMyBookings from '@/components/events/FindMyBookings';

export const metadata: Metadata = { title: 'Find my bookings' };

/**
 * Every booking made with one email address (D-3).
 *
 * Public and unguarded. The emailed code is the whole of the authorisation — there
 * is no account here, which is the point: a company that attends events without ever
 * joining still needs its own invoices.
 */
export default function MyBookingsPage() {
  return <FindMyBookings />;
}
```

Add `myBookings: '/my-bookings'` to `ROUTES` in `constants/routes.ts`, and confirm it is treated as a public path by whatever list `RedirectIfAuthenticated` and the middleware consult.

- [ ] **Step 4: Verify both flag states in the browser**

With `events.booking_lookup_enabled` off: `/my-bookings` shows the not-available state that a 404 from the API produces. With it on: request a code, read it with `npm run otp`, enter it, see the bookings, download an invoice. Then set it back to off.

Run: `cd customer && npm run lint && npx tsc --noEmit && npm run build`

- [ ] **Step 5: Commit** (ask the user first)

```bash
git add customer/src
git commit -m "feat(events): add the find-my-bookings page for guests"
```

---

### Task 11: Self-test and documentation

**Files:**
- Modify: `docs/api-specification.md`
- Modify: `docs/implementation-status.md`

- [ ] **Step 1: Run everything**

```bash
cd backend && npm test && npm run typecheck && npm run lint && npm run db:check-comments
cd ../customer && npm run lint && npx tsc --noEmit && npm run build
```

All must pass.

- [ ] **Step 2: Confirm the switches still default to off**

Query the two rows and confirm both are `false`. **A deployment that ships either flag on has not been asked for.**

```sql
SELECT key, value FROM "SystemSettings" WHERE key IN ('events.guest_booking_otp','events.booking_lookup_enabled');
```

- [ ] **Step 3: Run the Self-Test Agent**

Use the existing Self-Test Agent as `CLAUDE.md` requires. Do not create another testing agent. Cover both flag states for the guest booking flow, and the member flow after linking.

- [ ] **Step 4: Document the endpoints**

Add the four new routes to `docs/api-specification.md` in the events section, and note both flags and their default in `docs/implementation-status.md`.

- [ ] **Step 5: Commit** (ask the user first)

```bash
git add docs
git commit -m "docs: record guest booking verification endpoints and flags"
```

---

## Rollout

1. Deploy with both flags `false`. Confirm guest booking still works. **Nothing has changed for anyone at this point** — that is the check that matters.
2. Turn on `events.guest_booking_otp`. Book an event as a guest with a real inbox. If codes do not arrive, turn it straight back off; bookings continue without verification.
3. Leave it on long enough that new bookings are being verified.
4. Turn on `events.booking_lookup_enabled` and test `/my-bookings`.
5. Run `npm run backfill:guest-booking-links -- --dry-run`, read the output, then run it for real.

## Open items for the client

Carried from the spec, not resolved here, and none of them block this work:

1. **Label wording** for linked rows — "Booked before membership" is a placeholder, not approved copy.
2. **Attendee emails are not matched.** Linking is on the company email only.
3. **No manual admin attach** for pre-existing unverified bookings. Those stay reachable through `/my-bookings` and are never auto-linked. If the association wants staff to be able to attach one after checking it by hand, that is a separate piece of work.
