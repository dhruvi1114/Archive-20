# API Specification

Contract-first: these signatures are frozen before coding starts each cycle. Cycle ids follow ADR-019. Auth column — `—` public, `M` member JWT, `A` admin JWT + listed permission.

## M1 — Auth & Account

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/auth/signup` | — | Create member login; sends OTP |
| POST | `/auth/verify-otp` | — | Verify signup OTP → activates login |
| POST | `/auth/resend-otp` | — | Resend OTP (throttled) |
| POST | `/auth/login` | — | Member login → access + refresh |
| POST | `/auth/refresh` | — | Rotate refresh token |
| POST | `/auth/logout` | M | Revoke current refresh token |
| POST | `/auth/forgot-password` | — | Email reset link |
| POST | `/auth/reset-password` | — | Consume token, set password |
| POST | `/auth/change-password` | M | Old + new password |
| GET | `/auth/me` | M | Session profile + member summary + capability flags |
| POST | `/auth/admin/login` | — | Admin login (separate audience) |
| POST | `/auth/admin/refresh` / `/logout` | A | Admin session ops |
| GET | `/auth/admin/me` | A | Admin profile + permission codes |

## M3 — Member profile, KYC, documents

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/members/me` | M | Full member profile + KYC completeness |
| PATCH | `/members/me` | M | Update non-critical fields (A-11) |
| POST | `/members/me/change-requests` | M | Request KYC-critical field change → approval |
| GET | `/members/me/change-requests` | M | List own change requests |
| GET | `/members/me/contacts` · POST · PATCH `/:id` · DELETE `/:id` | M | Contact persons |
| GET | `/members/me/addresses` · POST · PATCH `/:id` · DELETE `/:id` | M | Addresses |
| GET | `/document-types?applies_to=` | M | Required document checklist |
| POST | `/members/me/documents` | M | Upload (multipart) |
| GET | `/members/me/documents` | M | List with verification status |
| GET | `/documents/:id/download` | M/A | Authorised stream (owner or permitted admin) |
| DELETE | `/members/me/documents/:id` | M | Remove a not-yet-verified document |
| GET | `/admin/members/:id/documents` | A `member.view` | Review documents |
| PATCH | `/admin/documents/:id/verify` | A `document.verify` | VERIFIED / REJECTED + remarks |

## M4 — Applications, approvals & activation

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/applications` | M | Create draft (one open per user) |
| GET | `/applications/me` | M | List own applications |
| GET | `/applications/:id` | M | Draft/status detail + stage timeline |
| PATCH | `/applications/:id` | M | Save draft / correct a returned application |
| POST | `/applications/:id/documents` | M | Upload application document |
| POST | `/applications/:id/submit` | M | Validate completeness → SUBMITTED + open ApprovalRequest |
| POST | `/applications/:id/withdraw` | M | Withdraw before decision |
| GET | `/admin/applications` | A `application.view` | Queue: filter status/stage/category, search, paginate |
| GET | `/admin/applications/:id` | A `application.view` | Full review payload incl. documents + history |
| POST | `/admin/applications/:id/approve` | A `application.approve` | Advance stage; final stage → activate member |
| POST | `/admin/applications/:id/reject` | A `application.reject` | Terminal reject + remarks (required) |
| POST | `/admin/applications/:id/return` | A `application.return` | Return for correction + remarks (required) |
| POST | `/admin/applications/:id/reassign` | A `application.reassign` | Move to another stage/approver |
| GET | `/admin/applications/:id/history` | A `application.view` | ApprovalActions timeline |
| GET | `/admin/approval-workflows` | A `workflow.view` | Workflow + stages (read-only MVP, ADR-011) |
| GET | `/admin/profile-change-requests` · POST `/:id/approve` · `/:id/reject` | A `member.approve_change` | Profile change approvals |

## M2 (masters) / M3 (member management) — Categories, tiers, fees, member management

| Method | Path | Auth |
|---|---|---|
| GET/POST `/admin/membership-categories`, GET/PATCH/DELETE `/:id` | A `category.view` / `category.manage` |
| GET/POST `/admin/membership-tiers`, GET/PATCH/DELETE `/:id` | A `category.manage` |
| GET/POST `/admin/fee-structures`, GET/PATCH `/:id` | A `fee.view` / `fee.manage` |
| GET `/admin/members` | A `member.view` — search, status/category/tier filters, paginate |
| GET `/admin/members/:id` | A `member.view` — profile, terms, invoices, documents, history |
| PATCH `/admin/members/:id` | A `member.manage` |
| POST `/admin/members/:id/suspend` · `/reactivate` · `/terminate` | A `member.status` — remarks required |
| PATCH `/admin/members/:id/category` | A `member.manage` — category/tier change, reason logged |
| GET `/admin/members/export` | A `member.export` — CSV/XLSX |

## M4 (invoice issuance) / M5 (payments) — Billing & payments

| Method | Path | Auth |
|---|---|---|
| GET `/invoices/me` · GET `/invoices/:id` | M |
| GET `/invoices/:id/pdf` | M |
| POST `/payments/initiate` | M — `{invoice_id}` → provider order |
| POST `/payments/:id/verify` | M — client-side confirmation (signature checked server-side) |
| GET `/payments/me` | M — history |
| GET `/receipts/:id/download` | M |
| POST `/webhooks/payments/:provider` | — signature-verified, idempotent |
| GET/POST `/admin/invoices` · GET/PATCH `/:id` | A `invoice.view` / `invoice.manage` |
| POST `/admin/invoices/:id/issue` · `/cancel` | A `invoice.manage` |
| GET `/admin/invoices/overdue` | A `invoice.view` |
| POST `/admin/payments/record` | A `payment.record` — offline payment (ManualProvider) |
| GET `/admin/payments` · `/admin/payments/reconciliation` | A `payment.view` |
| POST `/admin/refunds` · POST `/admin/refunds/:id/approve` | A `refund.manage` |

## M6 — Renewal

| Method | Path | Auth |
|---|---|---|
| GET `/membership/me/term` | M — current term, expiry, renewal eligibility |
| POST `/membership/me/renew` | M — creates renewal term + invoice |
| GET `/membership/me/terms` | M — renewal history |
| GET `/admin/renewals/due` | A `renewal.view` — due/expiring/expired buckets |
| POST `/admin/renewals/:memberId/initiate` | A `renewal.manage` |
| POST `/admin/renewals/:termId/extend-grace` | A `renewal.manage` |

## M7 — Events

| Method | Path | Auth |
|---|---|---|
| GET `/public/events` · GET `/public/events/:slug` | — |
| GET `/events` · `/events/:slug` | M — incl. member-only events |
| POST `/events/:id/register` | M — free → CONFIRMED; paid → PENDING_PAYMENT + invoice |
| DELETE `/events/:id/register` | M — cancel |
| GET `/events/me/registrations` | M |
| GET/POST `/admin/events` · GET/PATCH/DELETE `/:id` | A `event.view` / `event.manage` |
| POST `/admin/events/:id/publish` · `/cancel` | A `event.manage` |
| GET `/admin/events/:id/registrations` | A `event.view` |
| POST `/admin/events/:id/attendance` | A `event.attendance` — check-in |
| GET `/admin/events/:id/attendees/export` | A `event.view` |

## M8 — Communication & notifications

| Method | Path | Auth |
|---|---|---|
| GET `/notices/me` · GET `/notices/:id` · POST `/notices/:id/read` | M |
| GET `/notifications/me` · POST `/notifications/:id/read` · POST `/notifications/read-all` | M |
| GET/POST `/admin/notices` · GET/PATCH `/:id` | A `notice.view` / `notice.manage` |
| POST `/admin/notices/:id/publish` | A `notice.publish` — fan-out inside a transaction |
| GET `/admin/notices/:id/recipients` | A `notice.view` — delivery + read stats |
| GET/PATCH `/admin/notification-templates` | A `template.manage` |
| GET `/admin/notifications` | A `notification.view` — outbox status, retry |

## M9 — Directory & public site

| Method | Path | Auth |
|---|---|---|
| GET `/public/directory` | — (if public per OQ-7) — approved, visible members, paginated |
| GET `/public/directory/:memberCode` | — public profile subset |
| GET `/directory` · `/directory/:memberCode` | M — richer field set |
| PATCH `/members/me/directory-visibility` | M |
| GET `/public/pages/:slug` · `/public/settings` | — homepage/about content + public settings |

## M10 — Dashboard, reports, org, audit, masters

| Method | Path | Auth |
|---|---|---|
| GET `/admin/dashboard/summary` | A `dashboard.view` — members, pending approvals, revenue, renewals due, events |
| GET `/admin/reports/members` · `/revenue` · `/renewals` · `/events` | A `report.view` |
| GET `/admin/reports/:type/export` | A `report.export` |
| GET/POST `/admin/designations` · `/admin/committees` · `/admin/committees/:id/members` | A `org.manage` |
| GET `/admin/audit-logs` | A `audit.view` — filter by entity/actor/date |
| GET/POST/PATCH `/admin/roles` · `/admin/permissions` · `/admin/admin-users` | A `rbac.manage` |
| GET/PATCH `/admin/system-settings` | A `settings.manage` |
| GET/POST/PATCH `/admin/document-types` | A `settings.manage` |

## Health

`GET /api/v1/health` — `{ status, uptime, db: "up"|"down", version }`. Unencrypted, unauthenticated, rate-limited.
