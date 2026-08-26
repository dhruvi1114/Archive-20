# Backup & Disaster Recovery

> Gap found in review: no backup or recovery policy existed anywhere in the plan. This platform holds KYC documents, approval history and financial records — losing them is unrecoverable by re-entry.

## 1. Targets

| Metric | Target (MVP) | Meaning |
|---|---|---|
| **RPO** (max data loss) | 24 h with nightly dumps · **15 min** if WAL archiving is enabled | How much work a restore may lose |
| **RTO** (max downtime) | 4 h | How long a full rebuild+restore may take |
| Retention | 7 daily · 4 weekly · 6 monthly | |
| Restore rehearsal | Before go-live, then quarterly | An untested backup is not a backup |

Recommendation: enable WAL archiving / PITR before go-live. A 24 h RPO on financial records means a bad day can cost a day of payments.

## 2. What must be backed up

| Asset | Method | Frequency |
|---|---|---|
| PostgreSQL | `pg_dump -Fc` (custom format, compressed) + optional WAL archive / RDS automated snapshots | Nightly (dump), continuous (WAL) |
| Uploads (KYC, invoices, receipts, notice attachments) | `rsync`/`restic` to off-host storage, or S3 versioning + lifecycle if Option B | Nightly, after the DB dump |
| `.env.<APP_ENV>` files and AES/JWT secrets | Encrypted store (password manager or KMS), **not** in the same place as the backups | On every change |
| Migration history | It is in git — see §7 | Every commit |

**DB and uploads must be backed up as a pair.** A restored database referencing files that no longer exist is a broken system: `MemberDocuments.file_path` would point at nothing, and no code path can regenerate a member's trade licence.

## 3. Nightly job (Option A)

```bash
#!/usr/bin/env bash
set -euo pipefail
TS=$(date +%F-%H%M); DEST=/var/backups/assoc
pg_dump -Fc -d "$DATABASE_URL" -f "$DEST/db-$TS.dump"
tar -czf "$DEST/uploads-$TS.tar.gz" -C /var/lib/assoc uploads
sha256sum "$DEST/db-$TS.dump" "$DEST/uploads-$TS.tar.gz" > "$DEST/checksums-$TS.txt"
rclone copy "$DEST" remote:assoc-backups/$TS      # OFF-HOST — a local-only copy is not a backup
find "$DEST" -mtime +7 -delete
```
Runs as a systemd timer or cron at a low-traffic hour. Failure must page someone — see `observability.md` §6. A silent backup failure is the classic way to discover you have no backups.

## 4. Restore procedure (rehearse it)

```bash
# 1. stop writes
pm2 stop api customer
# 2. restore DB into a fresh database, never over a live one
createdb assoc_restore
pg_restore -d assoc_restore --clean --if-exists db-2026-08-11-0200.dump
# 3. restore uploads
tar -xzf uploads-2026-08-11-0200.tar.gz -C /var/lib/assoc
# 4. verify BEFORE cutover
psql -d assoc_restore -c 'SELECT count(*) FROM "Members"; SELECT count(*) FROM "Invoices"; SELECT max("createdAt") FROM "AuditLogs";'
npm run db:check-comments
npx prisma migrate status          # schema must match the deployed build
# 5. cut over (repoint DATABASE_URL), start, smoke test
pm2 start api customer && node run.js --only=health,crypto,schema,auth
```

## 4b. Rehearsal log

| Date | Result |
|---|---|
| 2026-08-12 (M0) | **PASS.** `scripts/backup.sh` produced an 84 KB custom-format dump + uploads archive + verified checksums in 1 s. Restored into a scratch database `assoc_restore_drill`: 12 public tables, 39 permissions, 4 roles, 2 applied migrations, **0 columns missing comments after restore**. Scratch DB dropped. Two findings: (a) `RCLONE_REMOTE` is unset, so the copy is local-only — **this is not yet a real backup**; (b) the shell's default `psql` role is not the app's role, so restore commands must be run with the app's credentials (`PGUSER`/`PGPASSWORD`) or they hang on an auth prompt. |

## 5. Consistency rules

- Take the uploads snapshot **after** the DB dump. Extra files with no DB row are harmless; DB rows with no file are not.
- A restored DB must be paired with a build whose migration history matches (`prisma migrate status` clean). Restoring an old DB under a newer build without re-running `migrate deploy` is a corruption path.
- Never restore production data into dev/staging without anonymising emails, phones and document paths first (see `security.md` §8).

## 6. Scenario playbook

| Scenario | Response |
|---|---|
| Accidental `DELETE`/bad migration | Restore last nightly into a scratch DB, extract the affected rows, replay forward. Do not restore over live if other tables have moved on. |
| Disk/host loss | Rebuild host from `deployment.md`, restore latest dump + uploads, repoint DNS. RTO 4 h. |
| Ransomware / compromised host | Off-host copies are the only trustworthy source. Rebuild clean, restore, **rotate every secret** (JWT, AES, DB, SMTP, gateway) before going live. |
| Corrupted single upload | Restore that path from the archive; `checksum_sha256` on the document row proves whether the restored file is the original. |
| Gateway payment recorded, DB rolled back | Reconciliation report (`billing-payment.md` §8) plus `PaymentWebhookEvents` raw payloads let Accounts replay missing payments. This is why raw webhook bodies are stored. |

## 7. Version control — BLOCKER

Review finding: **the project is not under version control.** Only `sarvadhi-sentinel/` has a `.git`. `backend/`, `customer/`, `admin/` and `docs/` are untracked.

Two agents editing the same tree with no history, no branches and no diff review is the highest-probability way to lose work in this project — higher than any hardware failure. M0 must not start before:
1. `git init` at the repo root (or one repo per app, matching the Elvee layout — user's call).
2. `.gitignore` covering `node_modules`, `.env*` (except `.env.example`), `dist`, `.next`, `uploads`, `reports`, `*.dump`.
3. An initial commit of the skeleton + these planning docs.
4. A branch-per-cycle convention: `m0-foundation`, `m1-auth-rbac`, … with the module plan file updated in the same branch.

## 8. Open decisions

| ID | Decision | Blocking? |
|---|---|---|
| OQ-10a | Host: single VPS vs AWS | Not for M0; needed before staging |
| OQ-10b | WAL/PITR enabled, or nightly dumps only (accepts a 24 h RPO on financial data) | Before go-live |
| OQ-11 | Off-host backup destination and who holds its credentials | Before go-live |
| OQ-12 | Git hosting and repo layout: one monorepo or three repos like Elvee | **Before M0** |
