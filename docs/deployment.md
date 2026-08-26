# Deployment

> Status: **NEEDS DECISION — OQ-10 (the client's choice, not ours).** The host is not chosen yet. This document specifies the topology and release process that apply to either option. Nothing here blocks M0.

## 0. Ownership (from the proposal — NFR-1, NFR-2, NFR-7)

| Item | Owner |
|---|---|
| Hosting/cloud account, domain, SSL | **Client.** "All business/member data belongs to the client and resides on the client's own hosting/cloud account." We deploy into their account; we do not procure it |
| Business and member data | **Client.** Sarvadhi accesses only as required for implementation and support |
| Source code | **Sarvadhi.** The client receives the deployed solution and agreed deliverables |
| Payment gateway, WhatsApp API, SMTP and accounting subscriptions | **Client**, per the Third-Party Costs clause |
| Backup destination + its credentials | **Client-owned**, operated by us during the support window (`backup-recovery.md`) |

Practical consequences: host spec, OS access and network rules must be agreed with the client before staging; secrets live in the client's account; a credentials handover list is part of go-live (§10).

## 1. Environments

| Env | `APP_ENV` | Purpose | Data |
|---|---|---|---|
| local | `local` | Developer machine. `decrypted_data` echoed in responses. | Disposable |
| dev | `dev` | Shared integration target for the two coding agents | Seeded, wipeable |
| staging | `staging` | Client UAT, production-shaped | Anonymised copy or seed |
| production | `production` | Live | Real |

`decrypted_data` is returned in `local` only. Verified by the Sentinel `crypto` suite against dev.

## 2. Topology (both options)

```
              ┌──── nginx (TLS terminate, HTTP/2, gzip/brotli) ────┐
 members ────▶│  assoc.example.org        → customer (Next.js :3000)│
 staff   ────▶│  admin.assoc.example.org  → admin (static build)    │
 both    ────▶│  api.assoc.example.org    → backend (Express :4000) │
              └───────────────────────────────────────────────────┘
                                   │
                        PostgreSQL 18 (private network only)
                                   │
                        uploads volume (private, non-web-root)
```

- Admin is a Vite SPA → static files served by nginx with an SPA fallback. No Node process.
- Customer is Next.js → Node process (SSR/ISR needed for public pages and SEO).
- Backend is a Node process behind nginx. **Never** exposed directly.
- PostgreSQL listens on the private interface only; no public 5432, ever.
- Uploads live on a volume outside every web root (see `file-storage.md`).

**Option A — single VPS** (cheapest, fits this scale): nginx + PM2 (or systemd units) + local PostgreSQL + local uploads volume.
**Option B — AWS**: ALB + EC2/ECS for API and customer, S3+CloudFront for admin static and uploads, RDS PostgreSQL, SES for mail.

Decision changes: storage adapter (`local` vs `s3`), mail transport (SMTP vs SES), backup mechanics (`pg_dump` cron vs RDS snapshots + PITR).

## 3. Process management (Option A)

PM2 with `ecosystem.config.js`: `api` (instances 1, `ENABLE_JOBS=true`), `customer` (instances 1). `pm2 startup` + `pm2 save` for boot persistence. Log rotation via `pm2-logrotate`, 14 days.

**Job-instance rule (ADR-009):** exactly one process may have `ENABLE_JOBS=true`. If the API is ever scaled to N instances, N−1 must set it false, or jobs double-fire (duplicate reminders, duplicate invoices).

## 4. Release procedure

```bash
# 0. pre-flight
npm run db:check-comments && npx prisma migrate status     # clean, no drift
node run.js                                                # Sentinel green on staging

# 1. backup FIRST (see backup-recovery.md) — non-negotiable before any migration
pg_dump -Fc -d "$DATABASE_URL" -f backups/pre-release-$(date +%F-%H%M).dump

# 2. build
npm ci && npm run build            # backend  (tsc)
npm ci && npm run build            # customer (next build)
npm ci && npm run build            # admin    (vite build → dist/)

# 3. migrate (API stopped for destructive migrations only)
npx prisma migrate deploy

# 4. release
pm2 reload api && pm2 reload customer
rsync admin/dist/ → nginx admin root

# 5. verify
curl -fsS https://api.../api/v1/health
node run.js --only=health,crypto,schema
```

`prisma migrate deploy` only. Never `migrate dev`, never `db push`, never `--accept-data-loss` on a shared environment.

## 5. Rollback

| Failure | Action |
|---|---|
| App-level bug, no migration in the release | `pm2 reload` the previous build (keep the last 3 build artefacts) |
| Bad migration, no data written yet | Restore the pre-release dump, redeploy previous build |
| Bad migration, data already written | Forward-fix migration (`migration-strategy.md`). Prisma has no down-migrations — this is why step 1 exists |

## 6. Configuration & secrets

- One `.env.<APP_ENV>` per host, `chmod 600`, owned by the app user, **never** in git (`.gitignore` verified in M0).
- Required keys, all validated at boot by `config.ts` (fail fast, never default): `DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET`, `CHIPER`, `TERIFF`, `PLAN`, `APP_LANGUAGES`, `PORT`, `CORS_ORIGINS`, `RATE_LIMIT_*`, `SMTP_*`, `STORAGE_DRIVER`, `STORAGE_PATH`/`S3_*`, `ENABLE_JOBS`, `SEED_SUPERADMIN_EMAIL`, `SEED_SUPERADMIN_PASSWORD`, `PAYMENT_PROVIDER` + provider keys, `LOG_LEVEL`, `PUBLIC_BASE_URL`.
- Frontends: `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_CHIPER`, `NEXT_PUBLIC_TERIFF`, `NEXT_PUBLIC_PLAN`, `NEXT_PUBLIC_BASE_URL`. **These are public by definition** — see `security.md` §4 for what that means for the encryption scheme.
- Secrets differ per environment. Never copy production keys to dev/staging.

## 7. nginx requirements

TLS 1.2+ with a valid certificate (Let's Encrypt + auto-renew), HSTS, HTTP→HTTPS redirect, `client_max_body_size` ≥ the largest allowed upload + 1 MB, gzip/brotli for JSON and static, proxy timeouts ≥ the longest legitimate request (exports), `X-Forwarded-For` + `X-Forwarded-Proto` passed through (`app.set('trust proxy', 1)` in Express so rate limiting and IP logging are real), and no directory listing anywhere.

## 8. CI (recommended, not blocking)

GitHub Actions on PR: `npm ci`, lint, typecheck, unit + integration tests against a Postgres service container, `prisma migrate deploy` on a scratch DB, `db:check-comments`. Sentinel runs on the deployed dev environment after merge.

## 8b. Database roles and the AuditLogs immutability grant

`database-design.md` §G requires `AuditLogs` to be append-only. M0 documents the statement but **does not execute it**, deliberately: locally the app connects as a superuser, and `REVOKE UPDATE, DELETE ON "AuditLogs"` against a superuser is a silent no-op — it would read as protection while providing none.

This belongs to provisioning. On every shared environment:

```sql
CREATE ROLE assoc_app LOGIN PASSWORD '…';          -- the app connects as this, never as superuser
GRANT CONNECT ON DATABASE assoc TO assoc_app;
GRANT USAGE ON SCHEMA public TO assoc_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO assoc_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO assoc_app;
REVOKE UPDATE, DELETE ON "AuditLogs" FROM assoc_app;   -- append-only, enforced by the database
REVOKE UPDATE, DELETE ON "ApprovalActions" FROM assoc_app;
```

`DATABASE_URL` on dev/staging/production must use `assoc_app`, not the superuser. The Sentinel `schema` suite asserts the revoke by attempting an `UPDATE "AuditLogs"` and requiring it to fail — that assertion is skipped in local where no such role exists (it would pass vacuously and lie).

## 9. Pre-production checklist

Migrations applied and `migrate status` clean · `db:check-comments` zero · seeds run (roles, permissions, templates, document types, super admin) · super-admin credentials rotated from the seed values · TLS valid · CORS restricted to the two real origins · rate limits on · `decrypted_data` absent from responses · uploads directory not reachable by URL · backup cron installed, off-host destination configured (`RCLONE_REMOTE`), and one restore rehearsed (`backup-recovery.md`) · app connects as `assoc_app`, not superuser, with the AuditLogs revoke applied (§8b) · health endpoint monitored · log rotation active · gateway webhook URL registered and signature secret set.

## 10. Handover & support obligations (NFR-3, NFR-4, NFR-5)

The proposal commits to 3 months of complimentary support post go-live, Mon-Sat 10:00-19:00 IST over email and WhatsApp, first response within 8 working hours, defects in delivered scope fixed at no cost. Warranty excludes client-side infrastructure, third-party integrations and unauthorised modification.

**Handover pack, produced at go-live (not after):**
1. Deployment runbook - this document, filled in with real hosts, paths and service names.
2. Credentials inventory - every env key, who holds it, how to rotate it. Delivered over a secure channel, never in an email body.
3. Backup + restore runbook (`backup-recovery.md`) with the last rehearsal date and result.
4. Admin operations guide - configuring categories/fees, running approvals, issuing invoices, publishing notices, reading the outbox and the audit log.
5. Monitoring inventory - what alerts exist, where they land, who acts (`observability.md` section 6).
6. Known limitations and deferred scope - **including the accounting integration deferral (PV-4)** and every still-open question.
7. Sentinel: how to run it, how to read a report, final green report attached.

**Defect intake during the support window:** reported by email/WhatsApp to the single point of contact, recorded with severity (Blocker/Major/Minor per `testing-strategy.md` section 8), reproduced against the Sentinel suite, fixed, then re-verified by a full Sentinel run before release. Anything traced to client infrastructure, a third-party outage or an unauthorised change is reported as out-of-warranty rather than silently absorbed.
