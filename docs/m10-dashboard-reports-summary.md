# M10 — Dashboard, Reports & Audit (plain summary)

**Date:** 2026-09-02 · **Status:** planned, not started · **Owner:** Agent B

---

## In one line

Staff can see what needs doing, pull the numbers they need, and prove who
changed what.

---

## What already exists (not part of this cycle)

| Thing | Where |
|---|---|
| System Settings | `/settings/system` — built and working |
| Approval Workflow | `/settings/workflow` |
| 7 masters pages | categories, fees, document types, company types, event types, locations, news categories |
| `AuditLogs` table | live, 110 actions defined, 20 backend files writing to it |
| Admin-user API | `modules/rbac` — full CRUD, guards already enforced |
| Excel export helper | `helpers/excel.ts` — used by events today |

The menu is already complete. Four pages behind it are stubs. That is deliberate —
each cycle swaps its `Placeholder` for the real page.

---

## What we are building, in order

### 1. Roles & Staff tabs — *cheapest, backend already done*

One page, two tabs, at `/settings/roles`.

- **Roles tab** — the permission matrix. Tick what an ACCOUNTS user may do.
- **Staff tab** — the people who sign in, and which role each holds.

**Example.** New accountant joins → create account → assign ACCOUNTS → she
inherits `report.view`, `report.export`, `invoice.view`. She leaves →
**deactivate, not delete**, so her audit rows still point at a real name.

**Guards already in the backend:** last super admin cannot be stood down · you
cannot deactivate yourself. Still to add: a role bound to a live approval stage
cannot be deleted.

Permission: `rbac.manage` (SUPER_ADMIN only).

---

### 2. Audit log screen — *data is already there, only the screen is missing*

Filter by entity · actor · action · date range. Same data feeds a **History tab**
on member, application and invoice pages.

**Example row** — Ramesh approves application 482:

```
actor        ADMIN #7
action       application.approved
entity       Applications #482
before       { "status": "UNDER_REVIEW" }
after        { "status": "APPROVED" }
when         2026-09-02 11:04
```

**Example of use.** A member disputes a rejection. Filter to that application and
the whole chain appears — submitted, verified, rejected, with the reason and who
did it. Twenty seconds instead of a phone chain.

**Rules already built into the table:**

- Append-only — no `updatedAt`, no `deletedAt`, no UPDATE/DELETE grant
- No foreign key on the actor — delete the staff member, the record survives
- Written in the same transaction as the change, so it can never claim something
  that did not happen
- `before` / `after` redacted, so a password hash can never land in the trail

Permission: `audit.view`.

---

### 3. Reports

Four reports. Filters → table on screen → Excel download.

| Report | Filters |
|---|---|
| Members | status, category, tier, city, state, search |
| Revenue | date range, period |
| Renewals due | date range |
| Event attendance | event |

**City and state — no chapters.** The association does not use chapters.

**Example.** Meena needs the AGM list: Status = ACTIVE, Category = Gold,
City = Surat → 238 members on screen → Export → `members-2026-09-02.xlsx` with
the filters written at the top of the sheet.

**Rules**

- Two permissions: `report.view` to see, `report.export` to download
- Always `.xlsx`, never CSV — through the shared `helpers/excel.ts`
- Export row count must equal the on-screen count
- Must run in budget on 5,000+ members and 20,000+ invoices, `EXPLAIN` verified

---

### 4. Dashboard — *board comes back ON*

Flip `SHOW_QUEUE_BOARD` to `true` in `admin/src/pages/Dashboard.tsx`, then wire
the counts.

It is a **work queue, not a stats wall.** Every box is something a person can act
on. A queue your role cannot act on is **absent, not greyed out**.

Six boxes: applications · documents to verify · profile change requests ·
overdue invoices · renewals due in 30 days · failed notifications.

| Role | Boxes shown |
|---|---|
| SUPER_ADMIN | all 6 (bypasses every permission check) |
| ADMIN | all 6 |
| APPROVER | applications, change requests |
| ACCOUNTS | invoices, renewals |

**The count rule — three states, never collapsed into zero:**

| Value | Means | Shows as |
|---|---|---|
| `undefined` | cycle not built yet | "Arrives in M6." |
| `null` | the call failed | "Count unavailable." |
| a number | real | **12** waiting for you |

A failed count must never render `0` — that reads as "nothing to do", which is
the one lie a work queue cannot tell.

**One label fix:** "Applications at your stage" is wrong for a super admin, who
owns every stage. Show "Open applications" for them.

Backend: `GET /admin/dashboard/summary`, one indexed query per tile, cached 60 s.
No dashboard number is ever computed in the frontend.

---

### 5. Organisation — **PARKED, do last**

Office bearers and committees: who is President, Secretary, Treasurer, with term
dates, and sub-committees nested under the Executive Committee.

**Set up once — the posts** (`Designations`). `rank` decides the display order,
because a committee list must show President first, not alphabetically.

| code | name | rank |
|---|---|---|
| PRESIDENT | President | 1 |
| VP | Vice President | 2 |
| SECRETARY | Secretary | 3 |
| TREASURER | Treasurer | 4 |

**Set up once — the bodies** (`Committees`). Self-referencing, so a
sub-committee sits under its parent.

| name | type | parent |
|---|---|---|
| Executive Committee | EXECUTIVE | — |
| Finance Sub-Committee | SUB_COMMITTEE | Executive Committee |
| Events Sub-Committee | SUB_COMMITTEE | Executive Committee |

**April 2026 — the AGM elects a new committee.** Admin opens
Work → Organisation → Executive Committee → Add member:

```
Member       [ search "Rajesh" → Patel Textiles Pvt Ltd (M-0142) ]
Designation  [ Treasurer ]
Term start   [ 01-Apr-2026 ]
Term end     [ 31-Mar-2027 ]
```

Member, not free text — an office bearer must be a real member of the
association, so the post stays correct when the contact person's phone or email
changes.

**The overlap warning.** Suresh's Treasurer term was never closed and still runs
to 30-Jun-2026, so saving shows:

```
Term overlap
Suresh Shah holds Treasurer of Executive Committee until 30-Jun-2026.
Rajesh Patel's term starts 01-Apr-2026 — 91 days overlap.

[ Close Suresh's term on 31-Mar-2026 ]   [ Save anyway ]   [ Cancel ]
```

A **warning, not a block** — real handovers do overlap, and two people genuinely
share a post during a transition. The job of the system is to make sure it was
noticed. The database enforces only the thing that is always wrong:
`term_end > term_start`.

**What the screen then shows:**

```
Executive Committee                              Term 2026-27
--------------------------------------------------------------
President        Amit Shah      Shah Fabrics     Apr 26 - Mar 27
Vice President   Kiran Mehta    Mehta Mills      Apr 26 - Mar 27
Secretary        Nilesh Joshi   Joshi Exports    Apr 26 - Mar 27
Treasurer        Rajesh Patel   Patel Textiles   Apr 26 - Mar 27
  - Finance Sub-Committee (3 members)
  - Events Sub-Committee (5 members)
```

`term_end = NULL` means "still serving, no fixed end".

**Next April the term turns over.** Nothing is deleted — Rajesh's row is closed
(`term_end` set, `is_active` false) and the new Treasurer is added. The table
becomes the association's history of office, so "who was Treasurer in 2025?"
stays answerable. Every change writes an audit row.

**Delete behaviour:** deleting a committee removes its membership rows
(`CASCADE`); a designation anyone has ever held cannot be deleted (`RESTRICT`);
a member who has held a post cannot be deleted (`RESTRICT`).

**What it does NOT do:** it grants no login access (that is the Roles screen), it
routes no approvals, and it appears on no public page.

**Parked because** nothing else reads these tables — it grants no login access,
routes no approvals, and appears on no public page.

**Three naming fixes before it is ever built:**

1. `designation` already means a member's own company job title
   ("Managing Director"). Rename the association post table to
   `OfficeBearerPosts`.
2. "Organisation" already names the association-identity card in System Settings
   (name, GSTIN, logo). Rename this screen to **Office Bearers**.
3. Drop the `CHAPTER` committee type and the `chapter_region` column.

---

## Decided

- Dashboard board **on**, all six boxes, super admin sees everything
- Reports = the four above, filtered by city/state, **no chapters**
- Organisation **parked to last**
- **Event profit / surplus report: dropped.** Explored it (GJEPC reports
  "Surplus/(Deficit)", in aggregate not per event, and holds pre-event money as a
  liability) and chose not to build it. No `EventExpenses` table.

## Still open

- **Audit log retention** — how many years before rows are archived?
  Default assumption: 7 years, since the trail covers invoices and payments.

---

## Build order

1. Freeze contracts — exact meaning of every dashboard number, report columns,
   audit filter set. Publish types first, then build.
2. Roles + Staff tabs (UI only)
3. Audit query API + screen + History tab
4. `modules/report` + Reports screen
5. Dashboard summary endpoint + turn the board on + super-admin label fix
6. *(later)* Organisation

All admin screens built from the `association-admin-ui` catalogue so they match
the existing pages.

**Sentinel `reports` suite gates the cycle:** every dashboard number matched
against an independently computed fixture · date-range boundaries inclusive /
exclusive as documented · export count = screen count · audit before/after
correct · last-super-admin removal blocked · role bound to a live approval stage
cannot be deleted.
