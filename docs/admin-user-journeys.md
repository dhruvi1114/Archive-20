# Admin User Journeys

---

## AJ-1 Start the day (any admin role)

**Persona** Association staff, desktop, many small decisions.
**Goal** See what needs me, in priority order.
**Start** Admin login → landing page is a **work queue**, not a stats wall.
**What it shows** Pending approvals at my stage (count + oldest age) · documents awaiting verification · overdue invoices · renewals due in 30 days · unpublished notices · failed notifications. Each row: what, why it needs attention, how old, one primary action.
**Completion** Every queue at zero, or explicitly deferred.
**Failure/recovery** A queue the role can't act on isn't shown at all (permission-scoped landing).

---

## AJ-2 Review and decide a membership application (APPROVER / ADMIN)

**Goal** Approve, return or reject with confidence and a record.
**Start** Queue row "New application — Shree Diamonds — 2 days at Document Verification".
**Decisions** Are documents genuine and complete? Right category? Approve / return / reject?
**Actions** Open the review screen: left = application data grouped as the member entered it, right = documents with inline preview and per-document Verify/Reject; bottom = decision bar (Approve · Return for correction · Reject), remarks box mandatory for return/reject.
**System response** Transactional stage advance (see `approval-workflow.md` §5); member notified; history row written; the queue refreshes and the next application is offered ("Next in queue →").
**Completion** Final approval → member record created, code issued, invoice generated. Toast states exactly that: "Approved. Member LGDGF/2026/0042 created, invoice INV/2026-27/00031 issued for ₹25,000."
**Failure/recovery** Another approver acted first → "This application was already approved by <name> at <time>" and the screen reloads read-only (no silent double-advance). Missing fee configuration → blocking dialog: "No active fee for Growers/Gold. Configure a fee structure before approving." with a deep link.

---

## AJ-3 Manage members (ADMIN)

**Goal** Find a member fast; change status with a reason.
**Actions** Member list (search company/code/GST, filter status/category/tier/expiry) → member detail with tabs: Profile · KYC documents · Membership terms · Invoices & payments · Events · Notices · History.
Suspend/reactivate/terminate open a confirmation naming the member and the consequence ("Suspending hides them from the directory and blocks event registration. They keep portal access.") and require a reason.
**System response** Status history row, notification to the member, audit log.
**Failure/recovery** Terminate with an unpaid invoice → warning listing the invoices, requires explicit acknowledgement.

---

## AJ-4 Configure categories, tiers and fees (ADMIN / ACCOUNTS)

**Goal** Set up what members can join and what it costs.
**Actions** Categories → tiers → fee structures with effective dates. Creating a fee that overlaps an existing active one is blocked with the conflicting row shown.
**Expected result** The form states the impact: "New applications in Growers/Gold from 01 Sep 2026 will be invoiced ₹30,000 + 18% GST. Existing invoices are unaffected."
**Failure/recovery** Deactivating a category in use → blocked, with the count of members/applications using it and the suggestion to deactivate instead of delete.

---

## AJ-5 Invoicing, payments, refunds (ACCOUNTS)

**Goal** Money in, correctly recorded.
**Actions** Invoice list (status/date/type filters, dues + overdue totals in the header) → issue, cancel, download PDF, send reminder. Record an offline payment (method, reference, date, proof). Reconciliation: upload the gateway settlement CSV → matched / missing / mismatched report. Refund: request → second admin approves → provider/manual refund → statuses update.
**Expected result** Every action states the downstream effect ("Recording ₹25,000 will mark INV/2026-27/00031 PAID and activate the membership until 11 Aug 2027").
**Failure/recovery** Amount exceeds balance due → blocked with the exact remaining balance. Duplicate reference → conflict warning showing the existing payment.

---

## AJ-6 Renewals (ADMIN / ACCOUNTS)

**Goal** Nobody lapses unnoticed.
**Actions** Renewal dashboard bucketed: expiring in 30/15/7 days · expired in grace · expired past grace. Bulk-generate renewal invoices; send reminders; extend grace for a specific member with a reason.
**Expected result** Counts move between buckets after each action; every send is visible in the notification outbox.

---

## AJ-7 Events (ADMIN)

**Goal** Run an event end to end.
**Actions** Create (draft) → set details, capacity, fee, registration window → publish (confirmation states it becomes visible to members/public and to how many) → monitor registrations → check in attendees on the day (search by name/code, one tap) → export attendee report.
**Failure/recovery** Cancelling a published event with paid registrations → blocking dialog listing paid registrations and requiring a refund decision before cancelling.

---

## AJ-8 Communication (ADMIN)

**Goal** Reach the right members, once.
**Actions** Compose notice/circular → choose audience (all / category / tier / selected) → **preview shows the exact recipient count before publishing** → publish → delivery report (queued/sent/failed/read).
**Expected result** "Published to 214 members. 214 in-app, 214 emails queued." Failures are listed and retryable.
**Failure/recovery** Audience resolves to 0 → publish blocked with the filter shown.

---

## AJ-9 RBAC & staff (SUPER_ADMIN)

**Goal** Least privilege, provably.
**Actions** Admin user list → create staff, assign roles; role editor shows the permission matrix as checkboxes grouped by module with a plain-language description per permission. Removing a permission shows who is affected.
**Failure/recovery** Cannot remove the last super admin; cannot delete a role bound to a live approval stage (message names the workflow).

---

## AJ-10 Audit & reports (ADMIN / ACCOUNTS)

**Goal** Answer "who did this and when" and "how are we doing".
**Actions** Audit log filtered by entity, actor, action, date range; every member/application/invoice detail screen has a History tab reading the same source. Reports: members by category/status, revenue by period, renewals due, event attendance — each exportable to CSV/XLSX with the applied filters recorded in the file header.

---

## Cross-journey rules

- Landing page = work queue, permission-scoped. No vanity metrics.
- Every destructive or financial action: confirmation naming the object + stating the consequence + writing an audit row.
- Every list: server-side pagination, explicit filters, saved default sort, visible result count.
- Every decision screen: the remarks the member will see are shown as they will be seen.
