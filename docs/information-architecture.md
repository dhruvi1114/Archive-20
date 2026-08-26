# Information Architecture

## 1. Customer portal (Next.js)

```
/                             Home (association, value, CTA)
/about                        About the federation
/events                       Public event list
/events/[slug]                Public event detail (+ Register CTA → login)
/directory                    Public member directory (if OQ-7 = public)
/directory/[memberCode]       Public member profile
/membership                   Categories, benefits, fees, how to apply
/contact                      Contact
/login  /signup  /verify-otp  /forgot-password  /reset-password

── authenticated (member shell: top bar + left nav) ──
/dashboard                    Next-action list
/application                  Current application (stepper or tracker)
/application/history          Past applications
/profile                      Company profile (editable / needs-approval split)
/profile/contacts             Contact persons
/profile/addresses            Addresses
/profile/documents            KYC documents + verification status
/profile/change-requests      Pending profile changes
/membership                   Current term, expiry, renew CTA, term history
/invoices                     Invoice list
/invoices/[id]                Invoice detail + Pay
/payments                     Payment history + receipts
/events/my                    My registrations
/notices                      Notices & circulars
/notifications                Bell feed
/directory (member view)      Richer directory
/settings                     Password, email/phone, directory visibility
```

Navigation rule: max 7 primary items — Dashboard · Application/Membership · Profile · Billing · Events · Notices · Directory. Everything else lives one level down.

## 2. Admin portal (React + Vite, React Router v6)

```
/login
/                             Work queue (permission-scoped landing)
/applications                 Queue (default: my stage, oldest first)
/applications/:id             Review + decide
/members                      List
/members/:id                  Detail (Profile · Documents · Terms · Billing · Events · Notices · History)
/members/change-requests      Profile change approvals
/masters/categories           Categories & tiers
/masters/fees                 Fee structures
/masters/document-types       Document types
/masters/designations         Designations
/masters/committees           Committees & chapters
/billing/invoices             Invoice list
/billing/invoices/:id         Invoice detail
/billing/payments             Payments
/billing/reconciliation       Settlement matching
/billing/refunds              Refunds
/renewals                     Due / grace / expired buckets
/events                       Event list
/events/:id                   Detail (Registrations · Attendance · Reports)
/communication/notices        Notices & circulars
/communication/notices/:id    Composer + audience preview + delivery report
/communication/templates      Notification templates
/communication/outbox         Notification delivery status
/reports                      Members · Revenue · Renewals · Events
/settings/roles               Roles & permission matrix
/settings/admin-users         Staff accounts
/settings/workflow            Approval workflow (read-only MVP)
/settings/system              System settings
/audit                        Audit log
```

Left nav groups: **Work** (queue, applications, members, renewals) · **Money** (invoices, payments, refunds, reconciliation) · **Engage** (events, notices, templates, outbox) · **Configure** (masters, roles, staff, workflow, settings) · **Audit**. Groups the current role cannot use are hidden entirely.

## 3. Content hierarchy per screen type

| Screen type | Order of information |
|---|---|
| Member dashboard | Blocking action → time-sensitive (payment/renewal) → informational (notices, events) → history |
| Member detail (admin) | Identity + status → what needs action → financial position → history |
| Queue | Age → subject → why it's here → primary action |
| Detail + decide | Subject data → supporting evidence (documents) → decision bar (sticky) |
| Financial | Totals → line items → payment state → actions |

## 4. URL & naming conventions

- Members are addressed publicly by `member_code`, never by database id.
- Events by `slug`. Everything internal by id.
- List filters live in the query string so a filtered view is shareable and back-button safe.
- No internal vocabulary in customer URLs (`/application`, not `/membership-applications`).

## 5. Cross-linking

Approval screen → member record (after approval) → invoices → payments → receipts, each reachable in one click, each with a History tab reading `AuditLogs` for that entity.
