# Observability

> Gap found in review: logging existed only as "use the winston logger". Nothing defined what is logged, what must never be logged, how failures surface, or how anyone learns that the nightly job stopped running.

## 1. Layers

| Layer | Answers | Where |
|---|---|---|
| Application logs | "What happened in this request?" | winston → stdout + rotated files |
| Audit log | "Who changed this business record, and from what to what?" | `AuditLogs` table (append-only) |
| Job runs | "Did the scheduled work run and succeed?" | `JobRuns` table |
| Notification outbox | "Did the member actually get told?" | `Notifications` table |
| Health/uptime | "Is it up right now?" | `/api/v1/health` + external monitor |

Audit is **not** logging. Logs are operational and rotate away; `AuditLogs` is a business record and is retained (§7).

## 2. Log format

JSON lines, one object per event:
```json
{"ts":"2026-08-12T09:14:22.118Z","level":"info","env":"production","requestId":"c8f1…","actorType":"ADMIN",
 "actorId":42,"method":"POST","url":"/api/v1/admin/applications/17/approve","status":200,"durationMs":184}
```
`requestId` comes from the `x-request-id` header or is generated per request, is attached to every log line in that request, and is returned in the error envelope so a user can quote it in a support message.

Levels: `error` (needs a human), `warn` (self-recovered — retry, 409, lockout), `info` (request completed, job completed, business milestone), `debug` (local/dev only). Production runs at `info`.

## 3. Never log — hard rules

Passwords, password hashes, OTP codes, JWTs, refresh tokens, reset tokens, AES keys, gateway secrets, webhook raw bodies containing card data, KYC field values (IEC/GST/PAN/trade licence numbers), document file contents, decrypted request payloads, full `req.body` of any auth or payment endpoint.

Enforced by a winston redaction formatter with a key denylist (`password`, `token`, `otp`, `secret`, `authorization`, `data`, `pan_number`, `gst_number`, `iec_code`, …) that recursively masks values before serialisation. Sentinel asserts a login and a payment produce no matching substring in the log output.

## 4. What is logged per request

`responseHandler` already logs method/url/status/latency; M0 extends it with `requestId`, `actorType`, `actorId`, response size and — for 4xx/5xx — the error `code`. Bodies are never logged. Slow requests (>1 s) log at `warn` with the route so N+1 regressions surface without a profiler.

## 5. Health & readiness

| Endpoint | Checks | Used by |
|---|---|---|
| `GET /api/v1/health` | process up, uptime, build version, `SELECT 1` against Postgres | uptime monitor, Sentinel, nginx |
| `GET /api/v1/health/ready` | health + pending-migration check + storage path writable | deploy gate |

Both unauthenticated, rate-limited, no internal detail beyond `up`/`down` per dependency.

## 6. Alerting (MVP-appropriate, no new infrastructure)

| Condition | Signal |
|---|---|
| `/health` fails 2 consecutive checks | External uptime monitor (UptimeRobot/BetterStack free tier) → email/WhatsApp to the ops owner |
| Uncaught exception / unhandled rejection | Log at `error` + email to `CRASH_MAIL` (Elvee already does this — port it), then exit; PM2 restarts |
| Nightly backup script fails | Non-zero exit → cron MAILTO + a `JobRuns` row with `status=FAILED` |
| Any job fails or does not run for 24 h | `GET /admin/dashboard/summary` surfaces a "jobs stale" tile from `JobRuns`; daily digest email to super admin |
| `Notifications` rows `FAILED` > 0 | Visible in the admin outbox (A-28) + counted on the dashboard |
| Payment webhook signature failures > 3/hour | `error` log + email — this is an attack signal (`payment-webhook-security.md` §6) |
| Disk > 85 % (uploads grow forever) | Host-level cron check → email |

Deliberately no Prometheus/Grafana/APM for MVP: this is a low-traffic association platform and the operational team is small. The table above is the minimum that prevents silent failure. Revisit if traffic or team size changes.

## 7. Retention

| Data | Retention | Note |
|---|---|---|
| Application log files | 14 days rotated (`pm2-logrotate` or `logrotate`) | |
| `AuditLogs` | **Indefinite for MVP** — needs a decision (OQ-13). Financial/approval audit typically 7 years in India | Partition or archive if it grows past ~10 M rows |
| `JobRuns` | 90 days, pruned by the daily job | |
| `Notifications` | 180 days for SENT, indefinite for FAILED until acknowledged | |
| `PaymentWebhookEvents` | Indefinite — this is the reconciliation source of truth | |

## 8. Debugging with encryption on

Encrypted payloads make network-tab debugging useless, which is the cost of ADR-004. Compensations: `decrypted_data` in `local`; `requestId` correlation end to end; `AuditLogs` before/after JSON for business changes; a local-only `npm run decrypt -- <ciphertext>` helper for pasting a captured payload from dev. Never add a "decrypt this for me" endpoint in any shared environment.

## 9. Ownership

Each module's plan file names the queries/tiles that prove that module is healthy (job ran, outbox drained, payments reconciled). "It deployed" is not evidence that it works.
