# M1 — Authentication, RBAC & App Shells

**Status:** AWAITING_APPROVAL (self-test green 2026-08-12) · **Migration owner:** Agent B · **Blocking OQ:** OQ-1 carried forward by user decision — the `rbac.md` §3 matrix is seeded as the working default and revisited at this cycle's approval gate · **Depends on:** M0 (identity schema, notification outbox)

## Goal
A member can sign up, verify, log in and stay logged in. Staff can log in and see only what their role permits — enforced by the backend, not the UI.

## Agent A — member auth (backend + customer)
- Backend `modules/auth` member half: signup (+ OTP), verify-otp, resend-otp, login, refresh (rotation), logout, forgot/reset password, change password, `/auth/me`.
- Bcrypt cost 12, lockout after 5 failures, throttles per `api-conventions.md` §9.
- OTP and password-reset emails are **queued to the M0 outbox** (ADR-015) against seeded templates — never sent inline from the auth service.
- Customer screens C-06…C-09, C-29: signup, OTP, login, forgot/reset, settings-password. All states from `screen-inventory.md`.
- Route protection + redirect-preserving deep links; token refresh interceptor.

## Agent B — admin auth + RBAC (backend + admin)
- `modules/auth` admin half (separate audience per ADR-002) + `modules/rbac`: roles, permissions, role-permission grants, admin users, `authenticateAdmin`, `authorize()/any/all` with a 60 s permission cache that revalidates against the DB.
- Migration: `AuthTokens`, `OtpCodes`, `PasswordResetTokens` + partial unique indexes.
- Seeds: permissions (every code in `rbac.md`), 4 roles + grants, one super admin from env (fails loudly if unset).
- Admin screens A-01 (login), A-02 (permission-scoped work-queue landing, empty until M3 fills it), and the nav permission gating.

## Contracts frozen
JWT claim shape (both audiences) · `AuthTokens` model · permission code list · `/auth/me` and `/auth/admin/me` payloads (incl. `perms[]`) · lockout/throttle numbers.

## Self-test
`auth`, `rbac` suites: signup→OTP→login→refresh→logout; wrong password 401; lockout at 5; member token on admin route 403; per-role allowed 2xx + forbidden 403; expired/tampered token 401; password never present in any response or log.

## Definition of done
- Both login flows work end to end with encryption on.
- Permission removal takes effect within 60 s without re-login.
- No default/hardcoded credentials anywhere.
- Rate limits verified; audit rows written for login, failed login, logout, role change.

## Approval checklist
Permission matrix signed off (OQ-1) · lockout/throttle values acceptable · session lengths (30 min access / 7 day member refresh) acceptable.

## Ownership deviation for this cycle (recorded per implementation-plan.md §3)
`implementation-plan.md` gives Agent A the member-facing backend modules. For M1 only, **Agent B owns the entire backend auth module** (member half *and* admin half) and Agent A owns the customer app plus the Sentinel auth/rbac suites.

Reason: member and admin auth share the token model, the lockout logic, the hashing policy and `AuthTokens`. Splitting one cohesive module across two agents in a repo with no version control (R-13) invites exactly the integration bug M0 already produced. Frontend/backend remains cleanly split; A is not idle — it owns 6 customer screens, route guards and two new Sentinel suites.
Reverts to the standard split at M2.

---

## Cycle record — 2026-08-12

**Sentinel:** `reports/smoke_2026-08-12-11-59-45_pass.md` — **PASS**. Suites: health · api · crypto · schema · auth (22 checks) · rbac (15 checks, all four roles) · customer · admin.

### Delivered
Backend: `modules/auth` (member + admin, ~2,900 lines incl. rbac), `authenticate`/`authorize` middleware with the 60 s DB-revalidated permission cache, migration `20260812093409_m1_add_auth_tokens_otp_reset` (`AuthTokens`, `OtpCodes`, `PasswordResetTokens`), per-role test-staff seed. Customer: signup, verify-otp, login, forgot-password, reset-password screens + `MemberRouteGuard`. Admin: real login, token refresh, permission-aware nav, work-queue landing. Sentinel: `auth` and `rbac` suites written, `admin` suite un-skipped, crypto probe moved onto `auth/login`.

Schema now **14 tables / 134 columns, every one commented** (ADR-013 holds).

### Both coding agents were stopped mid-cycle
The user halted them. Their work was ~complete; the Planning Agent verified it, found and fixed the remaining defects inline, and ran the gate. No agent was relaunched.

### Defects found by the gate and fixed
| # | Finding | Verdict |
|---|---|---|
| 1 | **Signup disclosed whether a phone number was registered** — duplicate phone → 409, fresh phone → 201, so a stranger could test any number for membership | **Real bug, fixed.** The account is now created without the number and the response is identical either way; the collision surfaces in M3's profile screen where the person is authenticated. `security.md` §2 |
| 2 | Anonymous `/dashboard` did not redirect to `/login` | **Not a bug.** Stale `.next` build predating the guard. Clean restart → `/login?next=%2Fdashboard`. Process fix recorded in `testing-strategy.md` §4 |
| 3 | Sentinel demanded `failed_login_count >= 5` alongside `locked_until` | **Test bug, fixed.** The service resets the counter when it locks; `locked_until` in the future is the invariant. The assertion was failing a correct implementation |
| 4 | Sentinel printed **pass** for three RBAC roles that had no credentials | **False green, fixed.** Now renders as a skip — and the roles are no longer skipped: a local/dev-only `seedTestAdmins` (refuses to run under staging/production, no default passwords) gives ADMIN, APPROVER and ACCOUNTS real accounts, so all four roles are exercised |

### OQ-1 note for your approval
The permission matrix is now **executable, not just documented**: the suite asserts each role's exact granted-code count (SUPER_ADMIN 39 · ADMIN 29 · APPROVER 12 · ACCOUNTS 16) plus negatives — `ADMIN` cannot `application.approve`, `APPROVER` cannot `member.manage`, `ACCOUNTS` cannot `member.status`. Those three are the judgement calls worth your eye. Changing any of them is still a re-seed, not a migration.

### Gaps carried into M2
Unchanged from M0: off-host backup destination (OQ-11), `AuditLogs` revoke needs a non-superuser role in provisioning, Next-family advisories. New: `SEED_TEST_ADMINS` credentials live in `.env.local` — they must never be set in staging or production (the seed refuses, but the env files should not carry them either).
