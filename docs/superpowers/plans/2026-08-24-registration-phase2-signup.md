# Registration Redesign — Phase 2: Public Registration & Post-Approval Access

> **Revised 2026-08-24** — supersedes the earlier “signup + OTP + post-login stepper” plan. See spec §5.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the five-field signup with the full GJEPC registration form **including three fixed KYC uploads**, submit directly to the admin queue, and implement **set-password-after-approve** (Option B). No password at register; no login until admin approves and the member sets a password.

**Architecture:** `POST /api/v1/auth/register` accepts **multipart** form JSON + three files (`GST_CERTIFICATE`, `PAN_DOCUMENT`, `TRADE_LICENCE`). One transaction writes `Users` (`PENDING_APPROVAL`, `password_hash` NULL), `Members`, `MemberCategories`, `MemberAddresses`, `MembershipApplication` (`SUBMITTED`), `ApplicationDocument` ×3, and starts the approval workflow. Captcha is stateless HMAC. On admin approve, email a set-password link (`PasswordResetToken` or dedicated initial-password flow) → `ACTIVE`. Customer: registration page + confirmation + set-password page. **Remove** application stepper for new applicants.

**Spec:** `docs/specs/2026-08-24-registration-redesign.md`

**Depends on:** Phase 1 complete (migration applied, masters endpoints, member column repair).

## Global Constraints

- **No test framework.** Verify with typecheck, lint, manual HTTP/browser.
- **Enumeration-safe** duplicate-email response; write nothing for existing verified emails.
- **No password field** on the registration form (spec D-4).
- **No signup OTP** for new flow — email proof happens at set-password after approve.
- **Three KYC files required** — codes are constants, not loaded from Document Types admin.
- `Users.full_name` ← company name (OQ-R5).
- Single transaction for registration; partial applicants impossible.
- Customer uses `Form` / `FormField` / `Input` / `Select`; no direct `antd` in pages.
- Empty `city_id` must be omitted/null, not `""`, before Zod validation.
- Use `ApiService` envelope pattern (not a raw `api` import).

---

## Revised task outline (2026-08-24)

| Task | What | Key deliverable |
|------|------|-----------------|
| 1 | Captcha | `GET /auth/captcha` — unchanged below |
| 2 | Register schema | `registerSchema` — **no password**; multipart field names for 3 files |
| 3 | Register service | `POST /auth/register` — transaction: User + Member + categories + address + Application SUBMITTED + 3 ApplicationDocuments |
| 4 | Set-password after approve | Block login for `PENDING_APPROVAL`; on approve email link; `POST /auth/set-initial-password` |
| 5 | Customer API | `AuthService.register(FormData)`, `captcha()`, masters loaders |
| 6 | Registration form UI | Full form + 3 file inputs + consent; **no password field** |
| 7 | Set-password page | `/set-password?token=…` from approval email |
| 8 | Remove stepper gate | New applicants skip post-login application stepper |

**Superseded:** OTP verification at signup, `POST /auth/signup` password flow, post-login document upload stepper (Phase 3 admin queue shows registration docs instead).

**JWT secret for captcha:** `environment.jwtSecret` (not `jwt.accessSecret`).

**Errors:** use `ERROR_TYPES.INVALID_REQUEST` / `VALIDATION_ERROR` — no `BAD_REQUEST`.

Detailed steps below retain useful field-level guidance; **ignore** any password, OTP, or `POST /auth/signup` references — use `register` instead.

---

**Files:**
- Create: `backend/src/modules/auth/captcha.service.ts`
- Modify: `backend/src/modules/auth/auth.controller.ts`
- Modify: `backend/src/modules/auth/auth.routes.ts`
- Modify: `backend/src/constant/endPoints.constant.ts`

**Interfaces:**
- Consumes: `environment` from `@config/config` (for the signing secret).
- Produces: `issueCaptcha(): { token: string; svg: string }` and `assertCaptcha(token: string, answer: string): void` (throws `AppError` with `auth.captchaInvalid`). Task 3's **register** service calls `assertCaptcha`. Route: `GET /api/v1/auth/captcha`.

**Context:** The captcha is stateless on purpose. A server-side store would need eviction, would not survive a restart, and would be a second thing to scale. Instead the answer is HMAC-signed together with an expiry and handed to the client as an opaque token; the client returns the token alongside what the user typed.

- [ ] **Step 1: Write the captcha service**

Create `backend/src/modules/auth/captcha.service.ts`:

```typescript
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import { environment } from '@config/config';
import { ERROR_TYPES } from '@constant/errorTypes.constant';
import { AppError } from '@utils/appError';

/**
 * A stateless captcha for the public registration form.
 *
 * The answer never touches the database. It is HMAC-signed together with an expiry
 * and handed back as an opaque token, so verification is a signature check rather
 * than a lookup: nothing to evict, nothing lost on restart, nothing to scale.
 *
 * This stops a casual script, not a determined attacker with an OCR library. That is
 * the correct ambition — the real defences on this endpoint are the rate limiter,
 * and a captcha that pretended otherwise would just be theatre with a
 * dependency on a third party.
 */

/** Ambiguous glyphs are excluded: 0/O and 1/l/I cost more support mail than they add entropy. */
const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';

const LENGTH = 6;
const TTL_MS = 10 * 60 * 1000;

const secret = (): string => {
  const value = environment.jwtSecret ?? process.env.JWT_SECRET;

  if (!value) {
    // Fail loudly at first use rather than silently signing with an empty key.
    throw new Error('captcha: no signing secret configured');
  }

  return value;
};

const sign = (answer: string, expiresAt: number): string =>
  createHmac('sha256', secret()).update(`${answer}.${expiresAt}`).digest('base64url');

const randomCode = (): string =>
  Array.from({ length: LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');

/**
 * The distortion is deliberate and mild: a rotated, jittered glyph per character plus
 * four crossing strokes. Enough to defeat naive pixel matching, still readable by a
 * member on a phone — an unreadable captcha is an abandoned registration.
 */
const renderSvg = (code: string): string => {
  const glyphs = [...code]
    .map((char, index) => {
      const x = 16 + index * 26;
      const y = 34 + randomInt(-4, 5);
      const rotate = randomInt(-24, 25);

      return `<text x="${x}" y="${y}" transform="rotate(${rotate} ${x} ${y})" font-family="Georgia,serif" font-size="30" font-weight="700" fill="#1e2a5a">${char}</text>`;
    })
    .join('');

  const strokes = Array.from({ length: 4 }, () => {
    const y1 = randomInt(6, 46);
    const y2 = randomInt(6, 46);

    return `<path d="M0 ${y1} Q 90 ${randomInt(0, 50)} 180 ${y2}" stroke="#1e2a5a" stroke-width="1.4" fill="none" opacity="0.7"/>`;
  }).join('');

  return `<svg xmlns="http://www.w3.org/2000/svg" width="180" height="52" viewBox="0 0 180 52" role="img" aria-label="Captcha image"><rect width="180" height="52" fill="#ffffff"/>${strokes}${glyphs}</svg>`;
};

export interface IssuedCaptcha {
  /** Opaque; the client returns it verbatim with the answer. */
  token: string;
  /** Inline SVG markup, safe to render as a data URI. */
  svg: string;
}

export const issueCaptcha = (): IssuedCaptcha => {
  const answer = randomCode();
  const expiresAt = Date.now() + TTL_MS;

  return {
    token: `${expiresAt}.${sign(answer, expiresAt)}`,
    svg: renderSvg(answer),
  };
};

const invalid = (): AppError =>
  new AppError({ errorType: ERROR_TYPES.BAD_REQUEST, messageKey: 'auth.captchaInvalid' });

/**
 * Throws unless `answer` matches the code inside `token` and the token is unexpired.
 *
 * Case-insensitive: the image is lower-case but a phone keyboard capitalises the
 * first character, and failing a member for their keyboard's autocorrect is a
 * support ticket, not a security win.
 */
export const assertCaptcha = (token: string, answer: string): void => {
  const [rawExpiry, signature] = token.split('.');

  if (!rawExpiry || !signature) throw invalid();

  const expiresAt = Number(rawExpiry);

  if (!Number.isFinite(expiresAt) || expiresAt < Date.now()) throw invalid();

  const expected = Buffer.from(sign(answer.trim().toLowerCase(), expiresAt));
  const actual = Buffer.from(signature);

  // Length differs → not equal, and timingSafeEqual would throw rather than return false.
  if (expected.length !== actual.length) throw invalid();

  if (!timingSafeEqual(expected, actual)) throw invalid();
};
```

- [ ] **Step 2: Add the endpoint constant**

In `backend/src/constant/endPoints.constant.ts`, inside `END_POINTS`:

```typescript
  CAPTCHA: '/captcha',
```

- [ ] **Step 3: Add the controller**

In `backend/src/modules/auth/auth.controller.ts`, following the file's existing handler shape:

```typescript
export const captcha = handler(async (_req, res) => {
  handleApiResponse(res, { responseType: RES_STATUS.GET, data: issueCaptcha() });
});
```

Add the import: `import { issueCaptcha } from '@modules/auth/captcha.service';`

- [ ] **Step 4: Mount the route**

In `backend/src/modules/auth/auth.routes.ts`, alongside the other unauthenticated routes:

```typescript
// Unauthenticated by definition — the registration form has no session. Rate-limited
// with the rest of /auth so it cannot be used to burn CPU on SVG generation.
authRouter.get(END_POINTS.CAPTCHA, controller.captcha);
```

- [ ] **Step 5: Add the message key**

Add to the English locale beside the other `auth.*` keys:

```json
  "auth.captchaInvalid": "That captcha code is wrong or has expired. Try the new one."
```

Mirror into every other locale file.

- [ ] **Step 6: Verify it issues**

Run: `cd backend && npm run dev` then in another shell:
```bash
curl -s localhost:3000/api/v1/auth/captcha | head -c 300
```
Expected: JSON with a `token` like `1789...ABC` and an `svg` string starting `<svg xmlns=`.

- [ ] **Step 7: Verify a wrong answer is rejected and a right one accepted**

Run:
```bash
cd backend && npx tsx -e "
import { issueCaptcha, assertCaptcha } from './src/modules/auth/captcha.service';
const c = issueCaptcha();
const code = /aria-label=\"Captcha image\"/.test(c.svg) ? c.svg.match(/>([a-z0-9])<\/text>/g)!.map(s => s.replace(/[><]|\/text/g,'')).join('') : '';
console.log('code =', code);
assertCaptcha(c.token, code);
console.log('correct answer: accepted');
try { assertCaptcha(c.token, 'zzzzzz'); console.log('FAIL: wrong answer accepted'); }
catch { console.log('wrong answer: rejected'); }
"
```
Expected: `correct answer: accepted` then `wrong answer: rejected`. If the first line throws, the glyph extraction regex failed — read the code out of the SVG by eye and pass it literally.

- [ ] **Step 8: Typecheck, lint, commit**

```bash
cd backend && npm run typecheck && npm run lint
git add backend/src/modules/auth backend/src/constant/endPoints.constant.ts backend/src/locales
git commit -m "feat(auth): stateless signed captcha for the public registration form"
```

---

### Task 2: Register request schema (revised — no password)

**Files:**
- Modify: `backend/src/modules/auth/auth.types.ts` (or equivalent)
- Create: `backend/src/modules/auth/register.schema.ts` if splitting from legacy signup

**Produces:** `registerSchema` and `RegisterInput` — every field in spec §4 **except password**. Multipart: `gst_certificate`, `pan_document`, `trade_licence` file fields validated in controller (size, mime). `category_ids` min 1 (Business Nature). `consent_accepted: true`.

> **Note:** Detailed Zod snippets below still show `signupSchema` + `password` — treat as field reference only; omit password and rename to `registerSchema`.

### Task 3: Register writes user, member, application, and KYC docs (revised)

**Endpoint:** `POST /api/v1/auth/register` (`multipart/form-data`)

**Transaction writes:**
1. `Users` — email, `full_name` = company name, `password_hash` NULL, `status` = `PENDING_APPROVAL`
2. `Members` — company fields, consent, `company_type_id`, PAN/GST
3. `MemberCategories` — all selected Business Nature ids
4. `MemberAddresses` — registered address + location FKs
5. `MembershipApplications` — `status` = `SUBMITTED`, `category_id` = first selected category
6. `ApplicationDocument` ×3 — fixed codes `GST_CERTIFICATE`, `PAN_DOCUMENT`, `TRADE_LICENCE`

**Enumeration-safe:** duplicate verified email → same success response, no writes.

> **Note:** Steps below reference `signup` and `password_hash` — follow the transaction list above instead.

### Task 4 (new): Set-password after admin approval

- Login rejects `PENDING_APPROVAL` with `auth.pendingApproval`
- On application approve: email set-password link (reuse or extend password-reset token table)
- `POST /auth/set-initial-password` — token + password → `Users.status` = `ACTIVE`, hash set
- Wire in `activation.service.ts` / approval path (Phase 3 admin triggers email)

---

### Task 2 (legacy detail): Expand the signup request schema

**Files:**
- Modify: `backend/src/modules/auth/auth.types.ts:54`

**Interfaces:**
- Consumes: nothing.
- Produces: the widened `signupSchema` and its inferred `SignupInput`, carrying every field in spec §4. Task 3 consumes it.

- [ ] **Step 1: Replace the schema**

In `backend/src/modules/auth/auth.types.ts`, replace:

```typescript
export const signupSchema = z.object({
  email,
  password: memberPassword,
  full_name: fullName,
  phone,
});
```

with:

```typescript
/** PAN: five letters, four digits, one letter. The fourth letter encodes the holder
 *  type, but validating that would reject legitimate edge cases the association has
 *  not asked us to reject. Shape only. */
const panNumber = z
  .string({ required_error: 'validation.requiredFields' })
  .trim()
  .toUpperCase()
  .regex(/^[A-Z]{5}\d{4}[A-Z]$/, 'auth.invalidPan');

/** GSTIN: 15 characters, the first two being the state code. Same reasoning — shape,
 *  not the checksum, because a wrong checksum rule blocks a real member on a Sunday. */
const gstin = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^\d{2}[A-Z]{5}\d{4}[A-Z]\d[A-Z\d]Z[A-Z\d]$/, 'auth.invalidGstin');

const referenceId = z
  .string({ required_error: 'validation.requiredFields' })
  .regex(/^\d+$/, 'validation.invalidId');

export const signupSchema = z
  .object({
    // --- account -----------------------------------------------------------
    email,
    password: memberPassword,
    pan_number: panNumber,
    gstin_holder: z.boolean({ required_error: 'validation.requiredFields' }),
    gst_number: gstin.optional(),
    /** The reference form's Company Category Yes/No. Stored, never read (spec OQ-R1). */
    company_category: z.boolean().optional(),

    // --- company -----------------------------------------------------------
    company_name: z
      .string({ required_error: 'validation.requiredFields' })
      .trim()
      .min(1, 'validation.requiredFields')
      .max(200, 'validation.tooLong'),
    company_type_id: referenceId,
    /** "Business Nature" on the form; MembershipCategories underneath (spec D-5). */
    category_ids: z
      .array(referenceId, { required_error: 'validation.requiredFields' })
      .min(1, 'validation.requiredFields')
      .max(20, 'validation.tooLong'),

    // --- address -----------------------------------------------------------
    address_line1: z
      .string({ required_error: 'validation.requiredFields' })
      .trim()
      .min(1, 'validation.requiredFields')
      .max(200, 'validation.tooLong'),
    address_line2: z.string().trim().max(200, 'validation.tooLong').optional(),
    pincode: z
      .string({ required_error: 'validation.requiredFields' })
      .trim()
      .regex(/^\d{6}$/, 'auth.invalidPincode'),
    country_id: referenceId,
    state_id: referenceId,
    /** Optional: a state with no seeded cities renders "No cities available" and the
     *  form must still be submittable (spec §4.4.3). */
    city_id: referenceId.optional(),

    // --- contact -----------------------------------------------------------
    phone,
    landline: z.string().trim().max(20, 'validation.tooLong').optional(),

    // --- terms -------------------------------------------------------------
    consent: z.literal(true, {
      errorMap: () => ({ message: 'auth.consentRequired' }),
    }),
    captcha_token: z.string({ required_error: 'validation.requiredFields' }).min(1),
    captcha_answer: z.string({ required_error: 'validation.requiredFields' }).trim().min(1),
  })
  // Cross-field, so it cannot live on the field: the GSTIN is required exactly when
  // the applicant said they hold one, and must be absent when they said they do not.
  // Enforcing only the first half would let "No" plus a GSTIN through, and that row
  // is then a lie the directory would print.
  .superRefine((input, ctx) => {
    if (input.gstin_holder && !input.gst_number) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['gst_number'],
        message: 'validation.requiredFields',
      });
    }

    if (!input.gstin_holder && input.gst_number) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['gst_number'],
        message: 'auth.gstinWithoutHolder',
      });
    }
  });
```

- [ ] **Step 2: Add the message keys**

```json
  "auth.invalidPan": "Enter a valid PAN, e.g. AABCS1234K.",
  "auth.invalidGstin": "Enter a valid 15-character GSTIN.",
  "auth.invalidPincode": "Enter a 6-digit pin code.",
  "auth.consentRequired": "You have to accept the consent statement to register.",
  "auth.gstinWithoutHolder": "You selected No for GSTIN holder, so leave the GSTIN blank."
```

Mirror into every locale file.

- [ ] **Step 3: Typecheck**

Run: `cd backend && npm run typecheck`
Expected: FAIL in `auth.service.ts` — `input.full_name` no longer exists on `SignupInput`. That is the expected failure; Task 3 fixes it.

- [ ] **Step 4: Do not commit yet** — committed with Task 3.

---

### Task 3 (legacy detail): Signup writes the whole registration in one transaction

**Files:**
- Modify: `backend/src/modules/auth/auth.service.ts:244`
- Modify: `backend/src/modules/member/member.repository.ts`

**Interfaces:**
- Consumes: `assertCaptcha` (Task 1), the widened `SignupInput` (Task 2), `setMemberCategories` (Phase 1 Task 5).
- Produces: `createMemberWithAddress(tx, data)` in `member.repository.ts`. Nothing downstream consumes it except signup.

**Context:** Today signup writes only `Users`; the `Members` row is provisioned lazily on first authenticated request (spec §3a.1). That lazy path stays — it is the fallback for accounts made before this change — but a registration through the new form arrives complete, so it writes the member eagerly.

- [ ] **Step 1: Add the member+address repository helper**

Append to `backend/src/modules/member/member.repository.ts`:

```typescript
/**
 * Create a member and its first address together.
 *
 * Nested create rather than two calls so the address cannot exist without its member
 * even momentarily, and so the caller gets one statement's worth of failure to handle
 * rather than two.
 */
export const createMemberWithAddress = (
  db: Db,
  data: {
    primary_user_id: bigint;
    company_name: string;
    company_type_id: bigint;
    pan_number: string;
    gstin_holder: boolean;
    gst_number: string | null;
    company_category: boolean | null;
    landline: string | null;
    consent_accepted_at: Date;
    consent_ip: string | null;
    address: {
      line1: string;
      line2: string | null;
      pincode: string;
      country_id: bigint;
      state_id: bigint;
      city_id: bigint | null;
      country: string;
      state: string;
      city: string;
    };
  },
) =>
  db.member.create({
    data: {
      primary_user_id: data.primary_user_id,
      company_name: data.company_name,
      company_type_id: data.company_type_id,
      pan_number: data.pan_number,
      gstin_holder: data.gstin_holder,
      gst_number: data.gst_number,
      company_category: data.company_category,
      landline: data.landline,
      consent_accepted_at: data.consent_accepted_at,
      consent_ip: data.consent_ip,
      status: 'DRAFT',
      addresses: {
        create: {
          address_type: 'REGISTERED',
          is_primary: true,
          line1: data.address.line1,
          line2: data.address.line2,
          pincode: data.address.pincode,
          country_id: data.address.country_id,
          state_id: data.address.state_id,
          city_id: data.address.city_id,
          // The text columns are the snapshot, resolved from the masters at write
          // time. A master renamed next year must not rewrite this address.
          country: data.address.country,
          state: data.address.state,
          city: data.address.city,
        },
      },
    },
  });
```

- [ ] **Step 2: Verify the captcha before anything else**

In `backend/src/modules/auth/auth.service.ts`, at the very top of `signup`, before the `findUserByEmail` call:

```typescript
  // First, and before the email lookup: a captcha that ran after the lookup would
  // let a script probe registration state at full speed and only fail at the end.
  assertCaptcha(input.captcha_token, input.captcha_answer);
```

Add the import: `import { assertCaptcha } from '@modules/auth/captcha.service';`

- [ ] **Step 3: Resolve the location names inside the transaction**

Still in `signup`, after the captcha check and before the transaction, resolve the masters so the address snapshot has real names and the FKs are proven to exist:

```typescript
  // Resolved before the transaction opens: these are four short reads that must not
  // hold a write transaction open, and a bad id should fail as a 400 rather than
  // rolling back a half-built registration.
  const [companyType, country, state, city] = await Promise.all([
    prisma.companyType.findFirst({
      where: { id: BigInt(input.company_type_id), deletedAt: null, is_active: true },
      select: { id: true },
    }),
    prisma.country.findFirst({
      where: { id: BigInt(input.country_id), deletedAt: null, is_active: true },
      select: { id: true, name: true },
    }),
    prisma.state.findFirst({
      where: { id: BigInt(input.state_id), deletedAt: null, is_active: true },
      select: { id: true, name: true, country_id: true },
    }),
    input.city_id
      ? prisma.city.findFirst({
          where: { id: BigInt(input.city_id), deletedAt: null, is_active: true },
          select: { id: true, name: true, state_id: true },
        })
      : Promise.resolve(null),
  ]);

  if (!companyType || !country || !state) {
    throw new AppError({ errorType: ERROR_TYPES.BAD_REQUEST, messageKey: 'validation.invalidId' });
  }

  // The cascade has to hold on the server too. A client can post any pair it likes,
  // and a Surat row filed under Kerala is a data error nobody notices until a
  // membership report is wrong.
  if (state.country_id !== country.id || (city && city.state_id !== state.id)) {
    throw new AppError({
      errorType: ERROR_TYPES.BAD_REQUEST,
      messageKey: 'auth.locationMismatch',
    });
  }

  const categoryIds = input.category_ids.map(BigInt);

  const liveCategories = await prisma.membershipCategory.count({
    where: { id: { in: categoryIds }, deletedAt: null, is_active: true },
  });

  if (liveCategories !== categoryIds.length) {
    throw new AppError({ errorType: ERROR_TYPES.BAD_REQUEST, messageKey: 'validation.invalidId' });
  }
```

- [ ] **Step 4: Write the member inside the existing transaction**

Replace the body of the final `prisma.$transaction` in `signup` with:

```typescript
  await prisma.$transaction(async (tx) => {
    const user = await repo.createUser(tx, {
      email: input.email,
      password_hash: passwordHash,
      // The form has no person-name field (spec OQ-R5). The company name is the
      // best available answer and is what the lazy provisioning path assumed in
      // reverse; a named signatory is a MemberContact the member adds later.
      full_name: input.company_name,
      phone: phoneClaimable ? phone : null,
    });

    const member = await memberRepo.createMemberWithAddress(tx, {
      primary_user_id: user.id,
      company_name: input.company_name,
      company_type_id: companyType.id,
      pan_number: input.pan_number,
      gstin_holder: input.gstin_holder,
      gst_number: input.gstin_holder ? (input.gst_number ?? null) : null,
      company_category: input.company_category ?? null,
      landline: input.landline ?? null,
      consent_accepted_at: new Date(),
      consent_ip: context.ip,
      address: {
        line1: input.address_line1,
        line2: input.address_line2 ?? null,
        pincode: input.pincode,
        country_id: country.id,
        state_id: state.id,
        city_id: city?.id ?? null,
        country: country.name,
        state: state.name,
        city: city?.name ?? '',
      },
    });

    await memberRepo.setMemberCategories(tx, member.id, categoryIds);

    await memberRepo.recordStatusChange(tx, {
      member_id: member.id,
      from_status: null,
      to_status: 'DRAFT',
      reason: 'Registered through the public form',
    });

    await issueSignupOtp(tx, { id: user.id, email: user.email, full_name: user.full_name });

    await writeAudit(tx, {
      action: AUDIT_ACTIONS.USER_SIGNED_UP,
      entityName: 'Users',
      entityId: user.id,
      actorType: ACTOR_TYPES.MEMBER,
      actorId: user.id,
      // The company name is not personal data and is the one field that makes this
      // audit row readable a year later. PAN, GSTIN and the address are omitted on
      // purpose — an audit log is not a second copy of the KYC record.
      after: { email: user.email, company_name: member.company_name, status: user.status },
      ip: context.ip,
      userAgent: context.userAgent,
      requestId: context.requestId,
    });
  });
```

Add the import: `import * as memberRepo from '@modules/member/member.repository';`

- [ ] **Step 5: Add the message key**

```json
  "auth.locationMismatch": "That city does not belong to the selected state."
```

- [ ] **Step 6: Typecheck and lint**

Run: `cd backend && npm run typecheck && npm run lint`
Expected: both exit 0.

- [ ] **Step 7: Register end to end against the running server**

Start the server, then:

```bash
CAPTCHA=$(curl -s localhost:3000/api/v1/auth/captcha)
echo "$CAPTCHA" | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];open('/tmp/c.svg','w').write(d['svg']);print(d['token'])"
```

Open `/tmp/c.svg`, read the code, then:

```bash
curl -s -X POST localhost:3000/api/v1/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{
    "email":"rakesh@shahdiamonds.test",
    "password":"Str0ng!Passw0rd",
    "pan_number":"AABCS1234K",
    "gstin_holder":true,
    "gst_number":"24AABCS1234K1Z5",
    "company_category":false,
    "company_name":"Shah Diamonds LLP",
    "company_type_id":"2",
    "category_ids":["1"],
    "address_line1":"401, Ratna Complex",
    "pincode":"395002",
    "country_id":"1",
    "state_id":"1",
    "city_id":"29",
    "phone":"+91 98250 12345",
    "consent":true,
    "captcha_token":"<TOKEN>",
    "captcha_answer":"<CODE>"
  }'
```

Expected: a success response. `category_ids` must name a category that actually exists — the seed deliberately creates none, so create one through the admin API first, or insert one directly for the check.

- [ ] **Step 8: Verify all five rows were written**

```bash
cd backend && npx prisma db execute --stdin <<'SQL'
SELECT u.email, m.company_name, m.pan_number, m.gstin_holder, m.consent_accepted_at IS NOT NULL AS consented,
       (SELECT count(*) FROM "MemberCategories" mc WHERE mc.member_id = m.id) AS categories,
       (SELECT count(*) FROM "MemberAddresses"  a WHERE a.member_id  = m.id) AS addresses
  FROM "Users" u JOIN "Members" m ON m.primary_user_id = u.id
 WHERE u.email = 'rakesh@shahdiamonds.test';
SQL
```
Expected: one row, `consented = t`, `categories = 1`, `addresses = 1`.

- [ ] **Step 9: Verify the transaction is atomic**

Repeat the Step 7 request with `"city_id":"999999"`. Expected: a 400, and **no** new `Users` row:

```bash
cd backend && npx prisma db execute --stdin <<'SQL'
SELECT count(*) FROM "Users" WHERE email = 'atomic-check@test.test';
SQL
```
Expected: `0`. A `1` means a write escaped the transaction.

- [ ] **Step 10: Verify enumeration-safety survived**

Submit the Step 7 request a second time with the same email but a fresh captcha and a different company name. Expected: the **same** success response as the first, and the company name in the database **unchanged** — the second request must write nothing.

- [ ] **Step 11: Commit**

```bash
git add backend/src/modules/auth backend/src/modules/member/member.repository.ts backend/src/locales
git commit -m "feat(auth): registration writes user, member, categories and address atomically"
```

---

### Task 4: Customer API client and types

**Files:**
- Modify: `customer/src/constants/endpoints.ts`
- Modify: `customer/src/services/AuthService.ts`
- Create: `customer/src/services/MastersService.ts`
- Create: `customer/src/types/registration.ts`

**Interfaces:**
- Consumes: the Phase 1 public endpoints and Task 1–3's signup contract.
- Produces: `MastersService.registrationOptions()`, `.states(countryId)`, `.cities(stateId)`, `.consentText()`; `AuthService.captcha()`; the `RegistrationValues` type. Task 5 and 6 consume all of them.

- [ ] **Step 1: Add the endpoints**

In `customer/src/constants/endpoints.ts`:

```typescript
  registrationOptions: '/public/registration-options',
  states: '/public/states',
  cities: '/public/cities',
  registrationConsent: '/public/registration-consent',
  captcha: '/auth/captcha',
```

- [ ] **Step 2: Add the types**

Create `customer/src/types/registration.ts`:

```typescript
/** A master row as the public form renders it: an id to submit, a label to show. */
export interface Option {
  id: string;
  name: string;
}

export interface RegistrationOptions {
  company_types: Option[];
  countries: Option[];
}

export interface Captcha {
  token: string;
  /** Raw SVG markup. Rendered through a data URI, never dangerouslySetInnerHTML. */
  svg: string;
}

/** Exactly the shape POST /auth/signup accepts. Ids are strings — BigInt does not
 *  survive JSON, and the backend parses them back. */
export interface RegistrationValues {
  email: string;
  password: string;
  pan_number: string;
  gstin_holder: boolean;
  gst_number: string;
  company_category: boolean | null;
  company_name: string;
  company_type_id: string;
  category_ids: string[];
  address_line1: string;
  address_line2: string;
  pincode: string;
  country_id: string;
  state_id: string;
  city_id: string;
  phone: string;
  landline: string;
  consent: boolean;
  captcha_token: string;
  captcha_answer: string;
}
```

- [ ] **Step 3: Add the masters service**

Create `customer/src/services/MastersService.ts`, following the shape of the existing `AuthService`:

```typescript
import { ENDPOINTS } from '@/constants/endpoints';
import type { Option, RegistrationOptions } from '@/types/registration';

import api from './api';

/**
 * The public master reads behind the registration form.
 *
 * States and cities are fetched on demand rather than shipped with the page: every
 * Indian city is over a hundred rows the applicant will use one of.
 */
const MastersService = {
  registrationOptions: async (): Promise<RegistrationOptions> =>
    (await api.get(ENDPOINTS.registrationOptions)).data.data,

  states: async (countryId: string): Promise<Option[]> =>
    (await api.get(ENDPOINTS.states, { params: { country_id: countryId } })).data.data,

  cities: async (stateId: string): Promise<Option[]> =>
    (await api.get(ENDPOINTS.cities, { params: { state_id: stateId } })).data.data,

  consentText: async (): Promise<string> =>
    (await api.get(ENDPOINTS.registrationConsent)).data.data.value,
};

export default MastersService;
```

Match the real response envelope — if the project's `api` client already unwraps `data.data`, drop the second `.data`.

- [ ] **Step 4: Extend AuthService**

In `customer/src/services/AuthService.ts`, add:

```typescript
  captcha: async (): Promise<Captcha> => (await api.get(ENDPOINTS.captcha)).data.data,
```

and widen the existing `signup` argument type to `RegistrationValues`.

- [ ] **Step 5: Typecheck**

Run: `cd customer && npx tsc --noEmit`
Expected: errors only in `SignupForm.tsx`, which still passes the old five-field shape. Task 6 fixes it.

- [ ] **Step 6: Commit**

```bash
git add customer/src/constants/endpoints.ts customer/src/services customer/src/types/registration.ts
git commit -m "feat(customer): API client for registration masters and captcha"
```

---

### Task 5: Registration field components

**Files:**
- Create: `customer/src/components/auth/RegistrationSection.tsx`
- Create: `customer/src/components/auth/RadioGroupField.tsx`
- Create: `customer/src/components/auth/CheckboxGroupField.tsx`
- Create: `customer/src/components/auth/CaptchaField.tsx`
- Create: `customer/src/components/auth/ConsentBox.tsx`

**Interfaces:**
- Consumes: `Field` from `@/components/ui/Field`, `MastersService`, `AuthService.captcha`.
- Produces: `RegistrationSection({title, children})`; `RadioGroupField({label, options, value, onChange, error, required, name})`; `CheckboxGroupField` with the same props but `value: string[]`; `CaptchaField({token, onTokenChange, value, onChange, error})`; `ConsentBox({checked, onChange, error})`. Task 6 composes all five.

- [ ] **Step 1: The section wrapper**

Create `customer/src/components/auth/RegistrationSection.tsx`:

```tsx
import type { ReactNode } from 'react';

/**
 * One titled band of the registration form.
 *
 * The dotted rule under the title is not decoration: the form asks for twenty
 * fields, and without a visible break between "who you are", "what your company is"
 * and "what you are agreeing to", it reads as one undifferentiated wall and people
 * lose their place in it.
 */
export default function RegistrationSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="flex flex-col gap-5">
      <div>
        <h2 className="text-lg font-medium text-accent">{title}</h2>
        <div className="mt-2 border-b border-dashed border-accent/40" />
      </div>
      <div className="grid gap-5 md:grid-cols-2 lg:grid-cols-3">{children}</div>
    </section>
  );
}
```

- [ ] **Step 2: The radio group**

Create `customer/src/components/auth/RadioGroupField.tsx`:

```tsx
'use client';

import { useId } from 'react';

import { Field } from '@/components/ui/Field';

export interface RadioOption {
  value: string;
  label: string;
}

/**
 * Native radios rather than a select.
 *
 * With four or fewer options, every choice is visible without a click — which is the
 * whole reason the reference form uses radios for Company Type and a dropdown for
 * Country. Native inputs also mean arrow-key navigation and screen-reader grouping
 * come free instead of being reimplemented.
 */
export default function RadioGroupField({
  label,
  name,
  options,
  value,
  onChange,
  error,
  required,
  columns = 2,
}: {
  label: string;
  name: string;
  options: RadioOption[];
  value: string;
  onChange: (value: string) => void;
  error?: string | undefined;
  required?: boolean;
  columns?: 1 | 2;
}) {
  const groupId = useId();

  return (
    <Field label={label} htmlFor={groupId} error={error} required={required}>
      <div
        role="radiogroup"
        aria-labelledby={groupId}
        aria-required={required || undefined}
        className={columns === 2 ? 'grid grid-cols-2 gap-x-4 gap-y-2' : 'flex flex-col gap-2'}
      >
        {options.map((option) => (
          <label key={option.value} className="flex cursor-pointer items-center gap-2 text-sm">
            <input
              type="radio"
              name={name}
              value={option.value}
              checked={value === option.value}
              onChange={() => onChange(option.value)}
              className="focus-ring h-4 w-4 accent-accent"
            />
            <span>{option.label}</span>
          </label>
        ))}
      </div>
    </Field>
  );
}
```

- [ ] **Step 3: The checkbox group**

Create `customer/src/components/auth/CheckboxGroupField.tsx`:

```tsx
'use client';

import { useId } from 'react';

import { Field } from '@/components/ui/Field';

export interface CheckboxOption {
  value: string;
  label: string;
}

/**
 * The form's "Business Nature" control. Multi-select, because a Surat firm is
 * routinely a manufacturer and an exporter both, and making them choose one loses
 * the fact the association actually wants for its reporting.
 */
export default function CheckboxGroupField({
  label,
  name,
  options,
  value,
  onChange,
  error,
  required,
  emptyText = 'No options configured yet',
}: {
  label: string;
  name: string;
  options: CheckboxOption[];
  value: string[];
  onChange: (value: string[]) => void;
  error?: string | undefined;
  required?: boolean;
  emptyText?: string;
}) {
  const groupId = useId();

  const toggle = (option: string) =>
    onChange(value.includes(option) ? value.filter((v) => v !== option) : [...value, option]);

  return (
    <Field label={label} htmlFor={groupId} error={error} required={required}>
      {options.length === 0 ? (
        <p className="text-sm text-fg-muted">{emptyText}</p>
      ) : (
        <div
          role="group"
          aria-labelledby={groupId}
          className="flex flex-wrap gap-x-4 gap-y-2"
        >
          {options.map((option) => (
            <label key={option.value} className="flex cursor-pointer items-center gap-2 text-sm">
              <input
                type="checkbox"
                name={name}
                value={option.value}
                checked={value.includes(option.value)}
                onChange={() => toggle(option.value)}
                className="focus-ring h-4 w-4 accent-accent"
              />
              <span>{option.label}</span>
            </label>
          ))}
        </div>
      )}
    </Field>
  );
}
```

- [ ] **Step 4: The captcha field**

Create `customer/src/components/auth/CaptchaField.tsx`:

```tsx
'use client';

import { useCallback, useEffect, useState } from 'react';

import Input from '@/components/ui/Input';
import AuthService from '@/services/AuthService';

/**
 * Fetches its own challenge and hands the token up.
 *
 * The SVG goes through a data URI on an `<img>` rather than
 * `dangerouslySetInnerHTML`. The markup is ours today, but a captcha image is
 * exactly the kind of endpoint that grows a third-party provider later, and an
 * `<img>` cannot execute whatever arrives.
 */
export default function CaptchaField({
  value,
  onChange,
  onTokenChange,
  error,
}: {
  value: string;
  onChange: (value: string) => void;
  onTokenChange: (token: string) => void;
  error?: string | undefined;
}) {
  const [svg, setSvg] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const issued = await AuthService.captcha();
      setSvg(issued.svg);
      onTokenChange(issued.token);
      onChange('');
    } finally {
      setLoading(false);
    }
  }, [onChange, onTokenChange]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return (
    <div className="flex flex-col gap-3">
      <Input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        label="Enter Captcha Code"
        placeholder="Enter Captcha Code"
        autoComplete="off"
        required
        error={error}
      />
      <div className="flex items-center gap-3">
        {svg ? (
          <img
            src={`data:image/svg+xml;utf8,${encodeURIComponent(svg)}`}
            alt="Captcha challenge"
            width={180}
            height={52}
            className="rounded-sm border border-border"
          />
        ) : (
          <div className="h-[52px] w-[180px] animate-pulse rounded-sm bg-bg-subtle" />
        )}
        <button
          type="button"
          onClick={() => void refresh()}
          disabled={loading}
          className="focus-ring rounded-sm p-2 text-fg-muted hover:text-fg"
          aria-label="Get a new captcha code"
        >
          ↻
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: The consent box**

Create `customer/src/components/auth/ConsentBox.tsx`:

```tsx
'use client';

import { useEffect, useState } from 'react';

import MastersService from '@/services/MastersService';

/**
 * The consent paragraph and its confirmation.
 *
 * The text is fetched rather than hard-coded so the secretariat can reword it
 * without a deploy — a consent statement is a legal artefact and legal artefacts get
 * reworded by people who do not open pull requests.
 *
 * The box scrolls rather than truncating: a consent the applicant could not read in
 * full is not a consent anyone would want to rely on.
 */
export default function ConsentBox({
  checked,
  onChange,
  error,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  error?: string | undefined;
}) {
  const [text, setText] = useState<string | null>(null);

  useEffect(() => {
    void MastersService.consentText()
      .then(setText)
      .catch(() => setText(null));
  }, []);

  return (
    <div className="flex flex-col gap-3">
      <div className="max-h-40 overflow-y-auto rounded-sm bg-bg-subtle p-4 text-sm leading-relaxed">
        {text ?? 'Loading the consent statement…'}
      </div>

      <label className="flex cursor-pointer items-start gap-2 text-sm">
        <input
          type="checkbox"
          checked={checked}
          onChange={(event) => onChange(event.target.checked)}
          className="focus-ring mt-1 h-4 w-4 accent-accent"
        />
        <span>
          I confirm that I have read and understood the Privacy Policy of the Association and
          the implications of granting this consent.
        </span>
      </label>

      {error ? <p className="text-sm text-status-danger-fg">{error}</p> : null}
    </div>
  );
}
```

- [ ] **Step 6: Typecheck**

Run: `cd customer && npx tsc --noEmit`
Expected: errors only in `SignupForm.tsx`. If `Field` is not exported by name from `@/components/ui/Field`, check the file and use its actual export.

- [ ] **Step 7: Commit**

```bash
git add customer/src/components/auth
git commit -m "feat(customer): field components for the registration form"
```

---

### Task 6: Rebuild the registration form

**Files:**
- Modify: `customer/src/components/auth/SignupForm.tsx` (full rewrite)
- Modify: `customer/src/app/(public)/signup/page.tsx` (widen the page container)

**Interfaces:**
- Consumes: everything from Tasks 4 and 5.
- Produces: the finished registration screen. Phase 3 depends on nothing from here.

- [ ] **Step 1: Rewrite the validation schema and defaults**

Replace the top half of `customer/src/components/auth/SignupForm.tsx` — the `SignupValues` interface, `schema` and `FIELD_LABELS` — with:

```typescript
import type { Option, RegistrationOptions, RegistrationValues } from '@/types/registration';

/**
 * Phone stays deliberately permissive: members are Surat trade firms who write their
 * number in half a dozen formats and the backend normalises it. That rule predates
 * this form and is not loosened or tightened here.
 */
const PHONE_PATTERN = /^\+?[0-9][0-9\s-]{7,18}$/;

const schema: yup.ObjectSchema<RegistrationValues> = yup.object({
  email: yup.string().trim().required('Required').email('Check for a missing @ or a typo'),
  password: yup
    .string()
    .required('Required')
    .max(MAX_PASSWORD_LENGTH, `Use ${MAX_PASSWORD_LENGTH} characters or fewer.`)
    .test(
      'policy',
      ({ value }) => passwordError(String(value ?? '')) ?? 'Required',
      (value) => isPasswordValid(String(value ?? '')),
    ),
  pan_number: yup
    .string()
    .trim()
    .required('Required')
    .matches(/^[A-Za-z]{5}\d{4}[A-Za-z]$/, 'Enter a valid PAN, e.g. AABCS1234K'),
  gstin_holder: yup.boolean().required('Required'),
  // Required exactly when the applicant says they hold a GSTIN. Mirrors the
  // backend's superRefine — the server is the authority, this is the fast answer.
  gst_number: yup.string().when('gstin_holder', {
    is: true,
    then: (rule) =>
      rule
        .trim()
        .required('Required')
        .matches(/^\d{2}[A-Za-z]{5}\d{4}[A-Za-z]\d[A-Za-z\d]Z[A-Za-z\d]$/, 'Enter a valid 15-character GSTIN'),
    otherwise: (rule) => rule.strip(),
  }),
  company_category: yup.boolean().nullable().defined(),
  company_name: yup.string().trim().required('Required').max(200, 'Use 200 characters or fewer.'),
  company_type_id: yup.string().required('Pick one'),
  category_ids: yup.array(yup.string().required()).min(1, 'Pick at least one').required(),
  address_line1: yup.string().trim().required('Required').max(200, 'Use 200 characters or fewer.'),
  address_line2: yup.string().trim().max(200, 'Use 200 characters or fewer.').default(''),
  pincode: yup.string().trim().required('Required').matches(/^\d{6}$/, 'Enter a 6-digit pin code'),
  country_id: yup.string().required('Required'),
  state_id: yup.string().required('Required'),
  // Optional: a state with no seeded cities must still be submittable.
  city_id: yup.string().default(''),
  phone: yup
    .string()
    .trim()
    .required('Required')
    .matches(PHONE_PATTERN, 'Use a valid mobile number, e.g. +91 98250 12345'),
  landline: yup.string().trim().max(20, 'Use 20 characters or fewer.').default(''),
  consent: yup.boolean().oneOf([true], 'You have to accept this to register').required(),
  captcha_token: yup.string().required('Reload the captcha and try again'),
  captcha_answer: yup.string().trim().required('Required'),
});

const DEFAULTS: RegistrationValues = {
  email: '', password: '', pan_number: '', gstin_holder: false, gst_number: '',
  company_category: null, company_name: '', company_type_id: '', category_ids: [],
  address_line1: '', address_line2: '', pincode: '', country_id: '', state_id: '',
  city_id: '', phone: '', landline: '', consent: false, captcha_token: '', captcha_answer: '',
};

const FIELD_LABELS: Record<string, string> = {
  email: 'Email address (Username)',
  password: 'Password',
  pan_number: 'Company PAN No',
  gstin_holder: 'GSTIN Holder Status',
  gst_number: 'Company GSTIN',
  company_category: 'Company Category',
  company_name: 'Company Name',
  company_type_id: 'Company Type',
  category_ids: 'Business Nature',
  address_line1: 'Address Line 1',
  address_line2: 'Address Line 2',
  pincode: 'Pin code',
  country_id: 'Country',
  state_id: 'State',
  city_id: 'City',
  phone: 'Mobile No',
  landline: 'Landline No',
  consent: 'Consent',
  captcha_answer: 'Captcha',
};

const YES_NO = [
  { value: 'yes', label: 'Yes' },
  { value: 'no', label: 'No' },
];
```

- [ ] **Step 2: Load the masters and drive the cascade**

Inside the component, above the existing `onSubmit`:

```typescript
  const [options, setOptions] = useState<RegistrationOptions>({ company_types: [], countries: [] });
  const [states, setStates] = useState<Option[]>([]);
  const [cities, setCities] = useState<Option[]>([]);
  const [loadingStates, setLoadingStates] = useState(false);
  const [loadingCities, setLoadingCities] = useState(false);

  useEffect(() => {
    void MastersService.registrationOptions().then(setOptions);
  }, []);

  /**
   * The cascade, as three rules rather than a web of effects:
   *   country changes → refetch states, clear state and city
   *   state changes   → refetch cities, clear city
   *   neither chosen  → the dependent select is disabled, not empty-and-clickable
   *
   * Clearing is what makes the rule safe. Keeping a stale Surat selected under a
   * newly-chosen Kerala is the exact data error the backend rejects, and the person
   * would not see it until submit.
   */
  const loadStates = useCallback(async (countryId: string) => {
    setLoadingStates(true);
    try {
      setStates(await MastersService.states(countryId));
    } finally {
      setLoadingStates(false);
    }
  }, []);

  const loadCities = useCallback(async (stateId: string) => {
    setLoadingCities(true);
    try {
      setCities(await MastersService.cities(stateId));
    } finally {
      setLoadingCities(false);
    }
  }, []);
```

The `Form` component exposes `useFormContext`; use `setValue` from it inside the `onChange` of the country and state selects to clear the dependents:

```typescript
  // In the Country select's onChange:
  //   field.onChange(value);
  //   setValue('state_id', ''); setValue('city_id', '');
  //   setCities([]); void loadStates(value);
  //
  // In the State select's onChange:
  //   field.onChange(value);
  //   setValue('city_id', '');
  //   void loadCities(value);
```

- [ ] **Step 3: Rewrite `onSubmit`**

```typescript
  const onSubmit = async (values: RegistrationValues) => {
    setFailure(null);
    setSubmitting(true);
    try {
      await AuthService.signup({
        ...values,
        email: values.email.trim(),
        pan_number: values.pan_number.trim().toUpperCase(),
        // Sent only when the applicant said they hold one; the backend rejects the
        // contradictory combination rather than quietly ignoring it.
        gst_number: values.gstin_holder ? values.gst_number.trim().toUpperCase() : '',
        company_name: values.company_name.trim(),
        phone: values.phone.trim(),
      });

      dispatch(setPendingVerificationEmail(values.email.trim()));
      dispatch(setSignupCompanyName(values.company_name.trim()));
      router.push(ROUTES.verifyOtp);
    } catch (error) {
      setFailure(describeAuthError(error));
    } finally {
      setSubmitting(false);
    }
  };
```

Keep the existing duplicate-email banner logic untouched — it still applies.

- [ ] **Step 4: Lay out the three sections**

Replace the form body. Each field is a `FormField` rendering the matching control. The GSTIN conditional:

```tsx
            <FormField<RegistrationValues, 'gst_number'>
              name="gst_number"
              render={({ field, error, id }) => {
                const holder = watch('gstin_holder');

                return (
                  <Input
                    {...field}
                    id={id}
                    label={FIELD_LABELS.gst_number}
                    /* "N/A" is shown, not stored. The submitted value is empty and
                       the backend writes NULL — a literal "N/A" in a GSTIN column is
                       a string that looks like data and is not. */
                    value={holder ? field.value : ''}
                    placeholder={holder ? 'Enter Company GSTIN' : 'N/A'}
                    disabled={!holder}
                    required={holder}
                    error={error}
                  />
                );
              }}
            />
```

And the section skeleton:

```tsx
        <div className="flex flex-col gap-10">
          <RegistrationSection title="Account Information">
            {/* email · pan_number · gstin_holder */}
            {/* password · gst_number · company_category */}
          </RegistrationSection>

          <RegistrationSection title="Company Information">
            {/* company_name · company_type_id · address_line1 */}
            {/* address_line2 · pincode · country_id */}
            {/* state_id · city_id · landline */}
            {/* phone · category_ids (spans two columns) */}
          </RegistrationSection>

          <RegistrationSection title="Terms of Agreement">
            {/* ConsentBox and CaptchaField, both spanning the full width */}
          </RegistrationSection>
        </div>
```

Give `category_ids`, `ConsentBox` and `CaptchaField` a `className="md:col-span-2 lg:col-span-3"` wrapper so they span the grid.

For the State select, pass `disabled={!watch('country_id')}` and `emptyText="Select a country first"`. For City, `disabled={!watch('state_id')}` and `emptyText="No cities available"`.

- [ ] **Step 5: Add the Reset button**

Beside the existing Submit:

```tsx
          <div className="flex gap-3">
            <Button type="submit" variant="primary" loading={submitting}>
              {submitting ? 'Creating your account' : 'Submit'}
            </Button>
            <Button type="button" variant="secondary" onClick={() => reset(DEFAULTS)}>
              Reset
            </Button>
          </div>
```

`reset` comes from `useFormContext`. Note that resetting clears the captcha answer but **not** the token — the image on screen is still the valid challenge.

- [ ] **Step 6: Widen the page**

In `customer/src/app/(public)/signup/page.tsx`, the auth card is sized for a narrow login form. Widen its container to `max-w-5xl` so three columns fit; leave the login and forgot-password pages alone.

- [ ] **Step 7: Typecheck and lint**

Run: `cd customer && npx tsc --noEmit && npm run lint`
Expected: both exit 0.

- [ ] **Step 8: Check it in a browser**

Run: `cd customer && npm run dev`, open `/signup`, and confirm each of these by hand:

1. Three titled sections, three columns on a desktop width, one column at 375px.
2. GSTIN Holder defaults to No, GSTIN is disabled and reads `N/A`. Switching to Yes enables it and marks it required.
3. Country defaults to nothing; State is disabled until a country is picked.
4. Picking Gujarat loads its cities; switching to Kerala clears the city and loads Kerala's.
5. The captcha image renders and the ↻ button replaces it.
6. Submitting empty shows the error summary with every required field listed.
7. A complete, valid submission lands on `/verify-otp`.

- [ ] **Step 9: Commit**

```bash
git add customer/src/components/auth/SignupForm.tsx "customer/src/app/(public)/signup/page.tsx"
git commit -m "feat(customer): full company registration form"
```

---

## Phase 2 exit criteria

- [ ] `npm run typecheck` and `npm run lint` pass in `backend/` and `customer/`
- [ ] `GET /auth/captcha` issues a token and SVG; a wrong answer is rejected
- [ ] A complete registration writes `Users` + `Members` + `MemberCategories` + `MemberAddresses` in one transaction
- [ ] A bad `city_id` yields 400 and writes nothing
- [ ] Re-registering a verified email returns the same success and writes nothing
- [ ] GSTIN Holder = No submits a NULL `gst_number`, not the string `N/A`
- [ ] The country → state → city cascade clears its dependents on every change
- [ ] The form is usable at 375px width

## Next

**Phase 3** — `docs/superpowers/plans/2026-08-24-registration-phase3-admin-portal.md`: admin queue with registration KYC, set-password email on approve, hide Document Types admin, location/company-type masters, flat-fee admin, member detail fields.
