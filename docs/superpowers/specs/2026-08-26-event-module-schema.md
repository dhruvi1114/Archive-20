# Event Module — Schema (M7 + team logins)

**Date:** 2026-08-26 · Companion to `2026-08-26-event-module-design.md`
Conventions per [database-design.md](../../database-design.md): table `PascalCasePlural`, column `snake_case`, `id BIGSERIAL PK`, money `Decimal(14,2)`, timestamps `createdAt/updatedAt/deletedAt`, every FK has an explicit `ON DELETE`.

Legend: `PK` · `FK→` · `U` unique · `CK` check · `SD` soft-delete.

---

## 0. Conventions for these tables (new rules, apply from here onward)

1. **Integer enums.** Every enum on a table created by this module is a `smallint` column with a documented code map — **not** a Postgres native enum and **not** a Prisma `enum`. Codes start at 0 and are append-only; a code is never reused.
   *Existing tables (M0–M5) keep their string enums.* Converting them would mean editing applied migrations, which the project forbids. The database is therefore string-enum for the old modules and int-enum for everything from M7 on — a deliberate, documented split.
2. **Primary keys stay `bigint`** (`BIGSERIAL`) on every table, so every FK matches its parent's type.
3. **No `uuid` columns.** `bigint` is the only key type. Anything exposed in a public link uses the existing random business codes instead — `EventRegistrations.registration_code` and `EventRegistrationAttendees.attendee_code` are already `varchar(30) U`, so a ticket link reads `/ticket/EVT-1042-2A9F` and never exposes a sequential id.
4. **FK actions** — `CASCADE` for owned children, `SET NULL` for pointers, `NO ACTION` everywhere else. `NO ACTION` is used in place of `RESTRICT`: identical behaviour in Postgres for non-deferred constraints, and it is the project's stated preference from here on.
5. **Every migration runs inside an explicit transaction.** Each generated `migration.sql` opens with `BEGIN;` and closes with `COMMIT;`. Any statement that cannot run in a transaction (`CREATE INDEX CONCURRENTLY`) is split into its own migration and marked in the file header.
6. **Every table and every column carries a `COMMENT ON`** (ADR-013). `npm run db:check-comments` must return zero rows before the migration is considered done.
7. **Every table carries the full audit block** — who made the row and who last changed it, not just when:

| Column | Type | Notes |
|---|---|---|
| createdAt | timestamptz | `default now()`, not null |
| created_by_user_id | bigint | FK→Users ON DELETE SET NULL, nullable |
| created_by_admin_id | bigint | FK→AdminUsers ON DELETE SET NULL, nullable |
| updatedAt | timestamptz | `default now()`, not null |
| updated_by_user_id | bigint | FK→Users ON DELETE SET NULL, nullable |
| updated_by_admin_id | bigint | FK→AdminUsers ON DELETE SET NULL, nullable |
| deletedAt | timestamptz | nullable — soft-delete tables only |

   Two nullable actor columns per event, not one generic column, because that is the pattern the project already uses (`AuthTokens.user_id` / `admin_user_id`). `CK NOT (created_by_user_id IS NOT NULL AND created_by_admin_id IS NOT NULL)` — at most one actor. **Both null means the system did it**: the nightly expiry sweep, a seed, or a guest with no login. Written once as a Prisma mixin and applied to every table below, so the tables are not re-listed with these six columns each time.

---

## 1. New tables — company team logins

### MemberUsers — many logins under one membership
| Column | Type | Notes |
|---|---|---|
| id | bigserial | PK |
| member_id | bigint | FK→Members ON DELETE CASCADE |
| user_id | bigint | FK→Users ON DELETE NO ACTION |
| member_role | smallint | `0=OWNER, 1=TEAM`, default 1 — finer permissions parked |
| status | smallint | `0=INVITED, 1=ACTIVE, 2=DEACTIVATED`, default 0 |
| invited_by_user_id | bigint | FK→Users ON DELETE SET NULL, nullable |
| accepted_at | timestamptz | nullable |
| deactivated_at | timestamptz | nullable |
| *audit block* | | see section 0.7 |

`U(member_id, user_id)` · partial unique: exactly one `member_role = 'OWNER'` per member · index `(member_id, status)`.
`Members.primary_user_id` stays and must always have a matching `OWNER` row here — enforced in the migration backfill.

### MemberTeamInvites
`id`, `member_id FK→Members ON DELETE CASCADE`, `email citext`, `full_name varchar(150)`, `designation varchar(100)`, `token_hash text U`, `invited_by_user_id FK→Users ON DELETE SET NULL`, `expires_at timestamptz`, `accepted_at timestamptz` nullable, `revoked_at` nullable, plus the audit block (section 0.7).
Partial unique `(member_id, email)` where `accepted_at IS NULL AND revoked_at IS NULL` — no duplicate open invites.

---

## 2. Changes to `Events`

**Added**
| Column | Type | Notes |
|---|---|---|
| visibility | smallint | `0=MEMBER_ONLY, 1=PUBLIC`, default 0 |
| venue_address_line1 | varchar(200) | |
| venue_address_line2 | varchar(200) | nullable |
| state | varchar(100) | |
| pincode | varchar(10) | |
| country | varchar(100) | default 'India' |
| map_url | text | nullable |
| requires_approval | boolean | default false — the approval checkbox |
| collect_food_preference | boolean | default true |
| collect_photo | boolean | default false |
| collect_gov_id | boolean | default false |
| seats_taken | int | default 0 — see section 7 |
| terms_version | varchar(20) | policy version shown at booking |

**Kept** `city`, `tax_rate`, `capacity`, `registration_opens_at`, `registration_closes_at`, `status`.
**Removed** `is_public` (replaced by `visibility`), `is_paid`, `fee_amount` — price now lives in `EventPriceTiers`.

**Constraints**
`CK end_at > start_at` · `CK capacity IS NULL OR capacity > 0` · `CK seats_taken >= 0` · `CK capacity IS NULL OR seats_taken <= capacity` · `CK registration_closes_at <= start_at`.

### EventPriceTiers — the date-based pricing
| Column | Type | Notes |
|---|---|---|
| id | bigserial | PK |
| event_id | bigint | FK→Events ON DELETE CASCADE |
| name | varchar(60) | "Early bird", "Regular", "Late" |
| starts_on | date | inclusive |
| ends_on | date | inclusive — a tier runs to the end of its last day |
| member_price | Decimal(14,2) | `CK >= 0` |
| non_member_price | Decimal(14,2) | `CK >= 0` |
| display_order | int | |

`CK ends_on >= starts_on` · **exclusion constraint** on `(event_id WITH =, daterange(starts_on, ends_on, '[]') WITH &&)` so two tiers can never overlap for one event · index `(event_id, starts_on)`.
A free event is one row with both prices at 0.

---

## 3. Changes to `EventRegistrations`

**Status becomes `smallint`** (was a string enum; the table is created fresh in M7, so no conversion is needed):

| Code | Meaning |
|---|---|
| 0 | `PENDING_APPROVAL` — only when `Events.requires_approval` |
| 1 | `PENDING_PAYMENT` |
| 2 | `PAYMENT_UNDER_VERIFICATION` |
| 3 | `CONFIRMED` |
| 4 | `EXPIRED` — hold ran out |
| 5 | `CANCELLED` — by member or admin, no refund |
| 6 | `REJECTED` — approval refused |
| 7 | `REFUNDED` — event cancelled by admin |

`WAITLISTED` is dropped — no waitlist. `Events.status` likewise becomes `smallint`: `0=DRAFT, 1=PUBLISHED, 2=CANCELLED, 3=COMPLETED`.

**Added**
| Column | Type | Notes |
|---|---|---|
| registrant_type | smallint | `0=MEMBER, 1=GUEST` |
| guest_registrant_id | bigint | FK→GuestRegistrants ON DELETE NO ACTION, nullable |
| price_tier_id | bigint | FK→EventPriceTiers ON DELETE NO ACTION — the tier in force at registration |
| subtotal / tax_amount / total_amount | Decimal(14,2) | frozen at registration |
| expires_at | timestamptz | nullable — the payment hold deadline |
| approved_at | timestamptz | nullable |
| approved_by_admin_id | bigint | FK→AdminUsers ON DELETE SET NULL, nullable |
| rejection_reason | text | nullable |
| terms_accepted_at | timestamptz | not null |
| terms_version | varchar(20) | not null |
| media_consent | boolean | default false |
| **billing snapshot** | | `billing_company_name`, `gst_number`, `pan_number`, `iec_code`, `billing_line1`, `billing_line2`, `billing_city`, `billing_state`, `billing_pincode`, `billing_country`, `contact_name`, `contact_email`, `contact_phone` |
| cancelled_by | smallint | `0=MEMBER, 1=ADMIN, 2=SYSTEM`, nullable |

**Changed** `member_id` stays nullable (guests) · `user_id` becomes nullable (guests have no login) · `attendee_count` becomes a derived count kept in step with the attendee rows (`CK attendee_count > 0`).

**Constraints**
`CK (registrant_type=0 AND member_id IS NOT NULL AND user_id IS NOT NULL AND guest_registrant_id IS NULL) OR (registrant_type=1 AND guest_registrant_id IS NOT NULL AND member_id IS NULL)`
`CK status <> 6 OR rejection_reason IS NOT NULL`
`CK status NOT IN (0,1) OR expires_at IS NOT NULL`
Partial unique `(event_id, member_id)` **where `status IN (0,1,2,3)` AND `deletedAt IS NULL`** — one live registration per company per event, while still allowing a re-booking after an EXPIRED or CANCELLED one.

### EventRegistrationAttendees — who is actually going
| Column | Type | Notes |
|---|---|---|
| id | bigserial | PK |
| registration_id | bigint | FK→EventRegistrations ON DELETE CASCADE |
| member_user_id | bigint | FK→MemberUsers ON DELETE SET NULL, nullable — source row, guests have none |
| attendee_code | varchar(30) | U — this person's own code |
| full_name | varchar(150) | snapshot |
| designation | varchar(100) | snapshot |
| email | citext | snapshot |
| phone | varchar(20) | snapshot |
| unit_price | Decimal(14,2) | **frozen price for this person** |
| food_preference | smallint | `0=VEG, 1=NON_VEG, 2=JAIN`, nullable |
| photo_path | text | nullable |
| id_type | smallint | `0=AADHAAR, 1=PAN, 2=PASSPORT, 3=DL, 4=VOTER`, nullable |
| id_number | varchar(50) | nullable |
| special_requirement | text | nullable |
| *audit block* | | see section 0.7 |

Index `(registration_id)` · index `(email)` for the attendee search.

### GuestRegistrants — non-member identity
`id`, `full_name varchar(150)`, `designation varchar(100)`, `company_name varchar(200)`, `email citext`, `phone varchar(20)`, `gst_number varchar(20)` nullable, `pan_number` nullable, `line1`, `line2`, `city`, `state`, `pincode varchar(10)`, `country default 'India'`, plus the audit block (section 0.7).
Index `(email)`. Not a login — no `password_hash`, no `Users` row.

---

## 4. Payment verification (no gateway yet)

### PaymentSubmissions — the "I have paid" claim
Generic on `Invoices`, so membership invoices reuse it.

| Column | Type | Notes |
|---|---|---|
| id | bigserial | PK |
| invoice_id | bigint | FK→Invoices ON DELETE NO ACTION |
| submitted_by_user_id | bigint | FK→Users ON DELETE SET NULL, nullable (guest = null) |
| submitted_by_guest_id | bigint | FK→GuestRegistrants ON DELETE SET NULL, nullable |
| method | smallint | `0=NEFT, 1=UPI, 2=CHEQUE, 3=CASH` |
| reference_no | varchar(100) | UTR / cheque no. |
| amount | Decimal(14,2) | `CK amount > 0` |
| paid_on | date | |
| proof_path | text | uploaded receipt |
| status | smallint | `0=PENDING, 1=VERIFIED, 2=REJECTED`, default 0 |
| rejection_reason | text | nullable |
| verified_by_admin_id | bigint | FK→AdminUsers ON DELETE SET NULL, nullable |
| verified_at | timestamptz | nullable |
| payment_id | bigint | FK→Payments ON DELETE SET NULL — set on verify |
| *audit block* | | see section 0.7 |

`CK status <> 2 OR rejection_reason IS NOT NULL` · partial unique: one `status = 0` submission per invoice · index `(status, createdAt)` for the admin queue.
On **Verify** a `Payments` row is created (`method`, `provider='MANUAL'`, `status=SUCCESS`) and the invoice moves to PAID — all in one transaction. This sits behind the existing provider interface ([A-5](../../assumptions.md)), so adding Razorpay later changes no table.

---

## 5. Settings rows

| key | value | value_type | group | is_public |
|---|---|---|---|---|
| `event.payment_hold_days` | 5 | NUMBER | events | false |
| `membership.grace_days` | 30 | NUMBER | membership | false |

There is **no** reminder setting. The sweep job derives reminder days from `event.payment_hold_days`: first at `ceil(hold/2)`, final at `hold - 1`, duplicates dropped. One number to change, and the two can never fall out of step.

---

## 6. Table dropped from this phase

`EventAttendance` is **not created now** — day-of check-in is out of scope. Nothing above references it, so it can be added later as a pure addition: `registration_attendee_id FK→EventRegistrationAttendees U`, `checked_in_at`, `checked_in_by_admin_id`, `notes`.

---

## 7. Capacity — enforced in SQL, never read-then-write

`Events.seats_taken` is a counter guarded by a check constraint. Booking N seats is one statement inside the registration transaction:

```sql
UPDATE "Events"
   SET seats_taken = seats_taken + :n
 WHERE id = :event_id
   AND status = 'PUBLISHED'
   AND (capacity IS NULL OR seats_taken + :n <= capacity)
RETURNING seats_taken;
```

Zero rows returned → not enough seats → the whole transaction rolls back and the user is told **before** any invoice exists. The `CK seats_taken <= capacity` is the backstop if any other code path ever writes the column. Releasing seats (expiry, cancel, reject) is the same statement with `- :n` and `CK seats_taken >= 0`.

Seats are taken at **registration**, not at payment — which is why a rejected approval or an expired hold must release them.

---

## 8. Indexes

| Table | Index | Serves |
|---|---|---|
| Events | `(status, visibility, start_at)` | public and member listings |
| Events | `(slug)` U | detail page |
| EventPriceTiers | `(event_id, starts_on)` | tier lookup at booking |
| EventRegistrations | `(event_id, status)` | attendee list + admin counts |
| EventRegistrations | `(status, expires_at)` | the nightly expiry/reminder sweep |
| EventRegistrations | `(member_id, registered_at)` | "my registrations" |
| EventRegistrationAttendees | `(registration_id)` · `(email)` | delegate list, search |
| PaymentSubmissions | `(status, createdAt)` | admin verification queue |
| MemberUsers | `(member_id, status)` | team screen, attendee picker |

---

## 9. Transactions that must be atomic

1. **Register** — seat update (section 7) + registration + attendee rows + invoice (paid events) → one transaction. Any failure rolls all of it back.
2. **Approve** — status change + invoice creation + `expires_at = now() + payment_hold_days` → one transaction.
3. **Verify payment** — submission VERIFIED + `Payments` row + invoice PAID + registration CONFIRMED → one transaction.
4. **Expire / cancel / reject** — status change + seat release → one transaction.
5. **Cancel event** — event CANCELLED + every paid registration REFUNDED + refund rows → one transaction.

---

## 10. Migration order

1. `MemberUsers` + `MemberTeamInvites`, backfill one `OWNER` row per existing member from `Members.primary_user_id`.
2. `Events` — add columns, backfill `visibility` from `is_public`, backfill `seats_taken` from existing confirmed registrations, then drop `is_public` / `is_paid` / `fee_amount`.
3. `EventPriceTiers`, backfilling one tier per existing paid event from its old `fee_amount`.
4. `GuestRegistrants`.
5. `EventRegistrations` — new columns, then the status-enum migration, then the new partial unique index.
6. `EventRegistrationAttendees`, backfilling one row per existing registration from `attendee_count`.
7. `PaymentSubmissions`.
8. Settings seed rows.

Each is a separate Prisma migration. No already-applied migration is edited.
