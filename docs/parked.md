# Parked work

Things deliberately not built, with the reason and what it would take. Not a
backlog of things nobody got to — each of these was decided against, and the
decision is recorded so it does not get re-litigated or, worse, quietly built.

Last reviewed: 2026-09-02.

---

## 1. Organisation — office bearers and committees

**Screen:** A-30 · **Nav:** Work → Organisation (`/masters/committees`, a Placeholder today)
**Requirement:** FR-15 Hierarchy & Designations

Who holds which post in which committee, with term dates: `Designations`,
`Committees` (self-referencing, so a sub-committee sits under a parent) and
`CommitteeMembers`. Adding somebody whose term overlaps the outgoing holder
warns rather than blocks — real handovers overlap.

**Why parked (2026-09-02, user decision):** nothing else in the platform reads
these tables. It grants no login access, routes no approvals, and appears on no
public page. Reports and the audit log unblock daily work; this is a record book
nothing consults.

**Three things to fix before it is ever built:**

1. **`designation` already means something else.** Member contacts carry a
   free-text one — "Managing Director" of the member's *own* company
   (`member.types.ts`). The M10 table means an *association* post. Rename it,
   e.g. `OfficeBearerPosts`, or the two will be confused in conversation and in
   code.
2. **"Organisation" already names something else.** The System Settings screen
   has an Organisation card — the association's own identity: display name,
   GSTIN, logo, registered address. Rename this screen to **Office Bearers**.
3. **Drop chapters.** `committee_type` is designed as
   `EXECUTIVE | SUB_COMMITTEE | CHAPTER` with a `chapter_region` column
   (`database-design.md` §G). The association does not use chapters — verified
   2026-09-02: the word appears in no migration, no Prisma model and no source
   file. Remove the enum value and the column before the migration is written.

**Rough size:** one migration, one admin screen, ~1.5 days.

---

## 2. Background report generation

**Spec:** `docs/specs/2026-09-02-saved-reports.md` §5

A report over a threshold would be saved `queued`, built by a background job,
stored through the storage adapter, and the requester notified when it is ready
— the `queued → running → ready → failed` path the Dribee module uses.

**Why parked (2026-09-02, user decision):** the association has 9 members and 6
invoices. Inline generation is instant and will stay instant for years. The
infrastructure is already here — `src/jobs/` for the worker, `helpers/storage.ts`
for the file, `notifications/outbox.ts` for the message — so switching it on
later is roughly half a day, not a project.

**What already ships regardless:** a report matching more than 1,048,576 rows is
**refused** at generate time with "narrow the filters", rather than producing a
file that has silently dropped rows.

**Prepared for, deliberately:**

- `GeneratedReports.status` already permits `queued`, `running` and `failed` in
  its CHECK constraint, though nothing writes them. Adding a value to a CHECK
  later is a second migration against the same table.
- `error_message` exists on the row for the `failed` case.
- What is **not** there yet is a `file_key` column: with inline generation there
  is no stored file, and the export is rebuilt from the snapshot on every
  download.

**One thing to fix rather than copy.** Dribee's report list does **not** poll —
verified 2026-09-02, the only timer on that page is a search debounce. A row
reading "Generating…" stays that way until the page is reloaded. Harmless while
generation is inline; a dead end the day the background path ships. Poll while
anything is `queued` or `running`.

**Rough size:** ~0.5 days.

---

## Not parked — in progress or done

For contrast, so this file is not mistaken for the whole picture:

| | |
|---|---|
| Reports (saved model) | **built** 2026-09-02 |
| Audit log screen | **built** 2026-09-02 |
| Dashboard work-queue tiles | **built** 2026-09-02 |
| Roles & Staff tabs | **built** 2026-09-02 |
| Role permission editor | **built** 2026-09-02 |
| History tab | **built** 2026-09-02 |
| Member Statement report | **built** 2026-09-02 |

---

## Open question, not parked

**Audit log retention.** How long `AuditLogs` rows are kept has never been
decided. Nothing prunes them today, so the answer is currently "forever" by
omission rather than by choice. Seven years is the usual Indian statutory answer
where records touch money, and this trail covers invoices and payments.

Generated reports already prune at one year (`report.prune`).
