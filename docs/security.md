# Security Review & Decisions

Consolidates the security posture. Where the plan accepts a weakness deliberately, it is stated as an accepted risk with its compensating control — not hidden.

## 1. Assets worth protecting

| Asset | Why it matters |
|---|---|
| KYC documents (IEC, GST, PAN, trade licence, certificates) | Personal + commercial identity data of member firms. Leak = regulatory and reputational damage |
| Member/company directory data | Commercially sensitive; competitor value |
| Approval decisions and remarks | Integrity: a forged approval creates a fraudulent member |
| Invoices, payments, refunds | Integrity + fraud target |
| Admin credentials and RBAC config | Full compromise path |
| AES keys, JWT secrets, gateway keys | Compromise of everything above |

## 2. Threat model (what we design against)

| Threat | Control |
|---|---|
| Credential stuffing / brute force | bcrypt cost 12, 5-attempt account lockout, per-(IP, identifier) throttle on **failed** sign-ins, OTP for signup |
| Privilege escalation member → admin | Separate tables + separate JWT audiences; `aud` checked before permissions (ADR-002) |
| Horizontal access (member reads another member's data) | Every member query scoped by `member_id` from the token; cross-access returns 404, never 403, so ids cannot be probed |
| Forged approval | Permission + stage-role check + row lock + append-only `ApprovalActions` |
| Payment tampering / replay | Server-side amount, signature verification, unique `(provider, event_id)`, idempotent handler (`payment-webhook-security.md`) |
| Private document leak | Files outside every web root, authorised streaming endpoint only (`file-storage.md`) |
| SQL injection | Prisma client + parameterised `$queryRaw` templates; sort/filter columns from an allowlist, never interpolated |
| XSS in notices/remarks | Rendered as text, never `dangerouslySetInnerHTML`; if rich text is ever needed, server-side sanitisation is required first (currently out of scope) |
| CSRF | Bearer tokens in headers, not cookies → not applicable. If cookie auth is ever adopted this must be revisited |
| Secrets in git | `.gitignore` for `.env*`, secret scan before the first push (§7 of `backup-recovery.md` is a blocker for exactly this reason) |
| Stack-trace / schema disclosure | `ErrorHandler` maps to fixed codes; no Prisma/SQL detail ever reaches the client |

## 3. Authentication & session

Per `rbac.md`: 30-min access tokens, rotating refresh tokens stored **hashed** in `AuthTokens`, revocation on logout/logout-all, lockout, member password ≥8 with letter+digit, admin ≥12.

**RECOMMENDATION (not in MVP scope):** 2FA for `SUPER_ADMIN` and `ACCOUNTS`. Those roles can change RBAC and move money. Cost is one TOTP library and one screen. Flagged as a decision, not silently added.

## 4. Encryption decision (ADR-004) — what it does and does not do

The scheme: AES-256-CBC over gzip, keys `CHIPER`/`TERIFF`/`PLAN` from env, request `{data: ciphertext}`, response `data` encrypted.

**Stated plainly:** the browser must hold the key, so it ships in `NEXT_PUBLIC_TERIFF`/`NEXT_PUBLIC_PLAN` and is readable by anyone who opens the bundle. This is **obfuscation of payloads in transit and in tooling**, not a confidentiality boundary against a determined attacker. It raises the effort for casual scraping and automated API abuse; it does not replace TLS, authn or authz.

Accepted because: user requirement (Elvee parity), reuse of frontend utils and Sentinel, and consistency across the team's two codebases.

Non-negotiable conditions attached to accepting it:
1. **HTTPS is mandatory in every non-local environment.** Without TLS the scheme is worse than useless — a fixed key + fixed IV makes traffic replayable.
2. **Authn/authz/validation always run after decryption.** Encryption grants nothing.
3. **Static IV is a known weakness** (R-5): identical plaintexts produce identical ciphertexts, leaking equality across requests. Accepted for MVP parity. Upgrade path: per-message random IV prefixed to the ciphertext, one change in `helpers/encryption.ts` + the frontends' `enc-dec.ts` + Sentinel `lib.js` — all three already share the same format, so it is a single coordinated change post-MVP.
4. **Different keys per environment**, rotated if a bundle key is ever suspected exposed. Rotation is a coordinated release of backend + both frontends (documented in `deployment.md`).
5. **`decrypted_data` never leaves `local`.** Sentinel asserts this on dev.
6. Secrets that must stay secret (JWT secret, gateway keys, SMTP password, DB password) are **backend-only** and never given a `NEXT_PUBLIC_` name.

## 5. Transport & headers

TLS 1.2+, HSTS, HTTP→HTTPS redirect. `helmet` defaults plus a conservative CSP for both frontends. CORS restricted to the two real origins per environment — **not** `origin: '*'` (Elvee's backend does that; do not copy it here). `app.set('trust proxy', 1)` so rate limiting and IP audit see the real client address behind nginx.

## 6. Rate limiting

Limits per `api-conventions.md` §9. The login limiter counts **failures only** (`skipSuccessfulRequests`): counting successes gave a legitimate account a budget of five sign-ins per quarter hour — a developer, a user on three devices, or the self-test harness would exhaust it and then be refused while holding the correct password. Failures are also the thing worth counting for credential stuffing. Per-account lockout is unchanged and independent. **Gap found in review:** `express-rate-limit` defaults to an in-memory store, which resets on restart and does not work across instances. For MVP single-instance this is acceptable; it must be stated, and if a second instance is ever added the store must move to Postgres or Redis. Logged as OQ-14.

## 7. Secrets management

Env files only, `chmod 600`, never in git, never in logs, never in the client bundle unless `NEXT_PUBLIC_` (and then treated as public — §4). Rotation procedure and owner per key documented at go-live. Seeded super-admin credentials come from env and **must be rotated before production** (checklist item in `deployment.md` §9).

## 8. Personal data (India DPDP Act 2023) — RECOMMENDATION

The platform stores personal and business identity data of Indian entities. Not legal advice, but the plan should acknowledge:
- A privacy policy and terms page on the public site (currently not in `screen-inventory.md` — gap).
- Purpose limitation: KYC documents used for verification only.
- A member's right to access/correct their data — partly satisfied by the profile + change-request flows; a full data export is not in scope and should be a conscious decision.
- Retention: how long documents of rejected applicants are kept (OQ-15).
- Anonymisation before copying production data to staging (`backup-recovery.md` §5).

## 9. Dependencies

`npm audit` in CI; no new runtime dependency without a line in the module plan file; versions pinned per `versions.md`. Avoid Elvee's habit of unused/duplicate deps (`fs`, `path`, `cloudfront` as package names) — the skeleton is clean and should stay clean.

## 10. Security acceptance per module (Sentinel §6)

Unauthenticated → 401 · wrong audience → 403 · lower privilege → 403 · other member's resource → 404 · injection string in search → normal empty result · oversize/wrong-type upload rejected · raw upload path unreachable → 404 · error bodies free of stack/SQL/table names · no secret substrings in logs.

## 11. Open security decisions

| ID | Decision | Class |
|---|---|---|
| OQ-14 | Rate-limit store when >1 API instance (Postgres/Redis) | NEEDS DECISION (before scaling) |
| OQ-15 | Retention of documents for rejected/withdrawn applicants | NEEDS DECISION (before go-live) |
| OQ-16 | 2FA for SUPER_ADMIN / ACCOUNTS | RECOMMENDATION |
| OQ-17 | Virus scanning of uploads (ClamAV) | RECOMMENDATION (`file-storage.md` §6) |
| OQ-18 | Privacy policy + terms pages and their content owner | NEEDS DECISION (before go-live) |
