# Authentication & RBAC

## 1. Authentication

| Aspect | Member (`Users`) | Admin (`AdminUsers`) |
|---|---|---|
| Login | email + password (OTP-verified at signup) | email + password |
| Access token | JWT, `aud: "member"`, 30 min | JWT, `aud: "admin"`, 30 min |
| Refresh token | opaque random, hashed in `AuthTokens`, 7 days, rotated on use | same, 1 day |
| Claims | `sub`, `aud`, `member_id`, `status`, `iat`, `exp`, `jti` | `sub`, `aud`, `roles[]`, `perms[]` hash, `is_super_admin` |
| Middleware | `authenticate` | `authenticateAdmin` |
| Password | bcrypt cost 12; min 8 chars, 1 letter + 1 number; never logged | same, min 12 chars |
| Lockout | 5 failed logins → 15 min lock (`failed_login_count`, `locked_until`) | same |

A member token presented to an admin route fails on `aud` before any permission check (ADR-002). Token revocation: `AuthTokens.revoked_at`; logout-all revokes every row for the subject.

`perms[]` is embedded for UI convenience but **the middleware re-reads the permission set from the DB (cached 60 s per admin) on every admin request** — a stale token can never grant a permission that was revoked.

## 2. Permission model

`Permissions.code = "<module>.<action>"`. Roles hold permissions; admins hold roles. `is_super_admin = true` bypasses the permission check (and is itself auditable).

```
authorize('application.approve')      // single
authorize.any('invoice.manage', 'payment.record')
authorize.all('member.manage', 'member.status')
```

## 3. Permission matrix — provisionally adopted (OQ-1 still unsigned)

> **Status 2026-08-12:** the user chose to carry OQ-1 into M1 rather than block on it. This matrix is therefore seeded as the working default. It is cheap to change: permissions and grants are **seed data**, not schema, so a revision is an idempotent re-seed, not a migration. Review it at the M1 approval gate — the longer it stays unsigned, the more admin UI is built assuming these boundaries.

Legend: ✔ granted · — denied

| Permission | SUPER_ADMIN | ADMIN | APPROVER | ACCOUNTS |
|---|:--:|:--:|:--:|:--:|
| `dashboard.view` | ✔ | ✔ | ✔ | ✔ |
| `member.view` | ✔ | ✔ | ✔ | ✔ |
| `member.manage` | ✔ | ✔ | — | — |
| `member.status` (suspend/reactivate/terminate) | ✔ | ✔ | — | — |
| `member.approve_change` | ✔ | ✔ | ✔ | — |
| `member.export` | ✔ | ✔ | — | ✔ |
| `application.view` | ✔ | ✔ | ✔ | — |
| `application.approve` | ✔ | ✔ | ✔ | — |
| `application.reject` | ✔ | ✔ | ✔ | — |
| `application.reassign` | ✔ | ✔ | — | — |
| `document.verify` | ✔ | ✔ | ✔ | — |
| `category.view` | ✔ | ✔ | ✔ | ✔ |
| `category.manage` | ✔ | ✔ | — | — |
| `fee.view` | ✔ | ✔ | — | ✔ |
| `fee.manage` | ✔ | — | — | ✔ |
| `invoice.view` | ✔ | ✔ | — | ✔ |
| `invoice.manage` | ✔ | — | — | ✔ |
| `payment.view` | ✔ | ✔ | — | ✔ |
| `payment.record` | ✔ | — | — | ✔ |
| `refund.manage` | ✔ | — | — | ✔ |
| `renewal.view` | ✔ | ✔ | — | ✔ |
| `renewal.manage` | ✔ | ✔ | — | ✔ |
| `event.view` | ✔ | ✔ | ✔ | ✔ |
| `event.manage` | ✔ | ✔ | — | — |
| `event.attendance` | ✔ | ✔ | — | — |
| `notice.view` | ✔ | ✔ | ✔ | — |
| `notice.manage` | ✔ | ✔ | — | — |
| `notice.publish` | ✔ | ✔ | — | — |
| `template.manage` | ✔ | — | — | — |
| `notification.view` | ✔ | ✔ | — | — |
| `report.view` | ✔ | ✔ | — | ✔ |
| `report.export` | ✔ | ✔ | — | ✔ |
| `org.manage` (designations/committees) | ✔ | ✔ | — | — |
| `audit.view` | ✔ | ✔ | — | — |
| `rbac.manage` | ✔ | — | — | — |
| `settings.manage` | ✔ | — | — | — |
| `workflow.view` | ✔ | ✔ | ✔ | — |
| `workflow.manage` | ✔ | — | — | — |

**These are defaults, not hard rules** (user decision, 2026-08-13). Approval authority is whatever `application.approve` is granted to, and moving it is a re-seed, not a code change. ADMIN holds it because ADMIN staffs stage 1, document verification (`prisma/seed/approvalWorkflow.ts`); without the permission the seeded workflow would ship with an unstaffable first stage. It does **not** follow that ADMIN can approve a committee stage — stage scoping is a separate check (§5). Same for every other row.

**Changed 2026-08-25 by `docs/specs/2026-08-25-reject-resubmit-flow.md`.** `application.return` is gone: Return retired (D-1) and Reject is now the single action that sends an application back, closing it only at the resubmission cap. ADMIN gained `application.reject` as a direct consequence — stage 1 is an ADMIN queue, and a reviewer who can pass an application but not fail one cannot do document verification at all. Stage scoping is unchanged and still stops ADMIN deciding the committee's stages. ACCOUNTS owns fees/invoices/refunds and not member status; only SUPER_ADMIN edits RBAC, templates, workflow and settings.

## 4. Approval-queue scoping (beyond permissions)

Holding `application.approve` is not enough. A request is actionable only if the approver's roles include `ApprovalStages.approver_role_id` of the application's **current** stage. Enforced in `ApprovalService`, not in the route guard, and returns `403 FORBIDDEN` with an i18n message.

## 5. Member-side authorization

Members have no roles. Every member endpoint resolves `member_id` from the token and scopes the query by it (`WHERE member_id = $me`). Never trust an id from the request body for ownership. Cross-member access returns `404 NOT_FOUND` (not 403) so ids cannot be probed.

## 6. Document access

`GET /documents/:id/download` allows: the owning member, or an admin with `member.view` (for member docs) / `application.view` (for application docs). Files live outside the static root; the endpoint streams with `Content-Disposition: attachment` and logs an `AuditLogs` row (`document.downloaded`).

## 7. Frontend behaviour

Both apps hide actions the permission set does not include, purely as UX. Every corresponding backend route enforces the same permission independently (master instructions §16). Self-test includes a negative case per role: call a forbidden endpoint directly with a valid lower-privilege token and assert 403.

## 8. Seed

`seed/permissions.ts` upserts every code above; `seed/roles.ts` upserts the four roles and their grants; `seed/superAdmin.ts` creates one super admin from `SEED_SUPERADMIN_EMAIL` / `SEED_SUPERADMIN_PASSWORD` env vars (fails loudly if unset — no default credentials in code).
