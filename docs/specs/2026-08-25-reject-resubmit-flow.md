# Reject and Resubmit Flow — Specification

**Date:** 2026-08-25
**Status:** Agreed and fully resolved on 2026-08-25 — no open questions. First implementation pass landed 2026-08-25; D-16 to D-19 are the second pass.
**Supersedes:** `docs/specs/2026-08-24-registration-redesign.md` **OQ-R6** ("Return for correction without login — not in v1"), and the two-action Return/Reject model in `docs/approval-workflow.md`.

---

## 1. Why

The reviewer today has four decisions — Approve, Return, Reject, Move to another stage — and two of them mean nearly the same thing to the applicant. Worse, per-document rejection and application rejection are disconnected: `DocumentsPanel.tsx` has to tell the reviewer in prose that "rejecting a file does not return the application", which means the obvious action does not do the obvious thing.

At the same time the applicant has no way back in. Registration creates the user as `PENDING_APPROVAL` with `password_hash = NULL`, and `auth.service.ts` refuses login for that status — so an application sent back for correction is unreachable by the person who must correct it.

This spec collapses the reviewer's choices to **Approve** and **Reject**, makes Reject the single button that carries the document-level marks, and gives the applicant a **login-free resubmit link** capped by a master setting.

---

## 2. Decisions taken

| # | Decision | Consequence |
|---|---|---|
| D-1 | **Two actions only: Approve and Reject.** Return is removed | `application.return` permission, `/return` route, `returnForCorrection` controller and the Return button all retire |
| D-2 | **Reject is not terminal while attempts remain.** It sends the application back to the applicant | Reject resolves to `RETURNED_FOR_CORRECTION` until the resubmission limit is reached, then to `REJECTED` |
| D-3 | **Remarks are mandatory on Reject** | Already enforced by `rejectSchema` and the DB CHECK; the dialog must match |
| D-4 | **Retries are capped by a master setting, not unlimited** | `application.max_resubmissions`, super-admin editable. Default changes from `0` (unlimited) to **3** |
| D-5 | **Reaching the cap closes the application permanently** | `REJECTED`, resubmit link dies, applicant must apply fresh |
| D-6 | **Per-document ✓/✗ is a mark, not a message.** Nothing reaches the applicant until the one Reject click | Document decisions stay local until the application-level decision commits |
| D-7 | **Approve is blocked while any required document is not `VERIFIED`** | The Actions card reads document state; the server enforces it too |
| D-8 | **The Reject dialog is pre-filled from the document marks** | Reviewer writes one overall note; the itemised reasons come from the ✗ marks |
| D-9 | **Resubmission happens without logging in**, through a signed token link | New public endpoints; the logged-in correction path in the customer app is removed |
| D-10 | **No account, no password, no login before final approval** | Set-password email fires only inside `activateApprovedApplication` |
| D-11 | **A resubmission re-enters at Stage 1** | Unchanged — `stageForResubmission` already does this |
| D-12 | **Verified documents survive a resubmission.** Only ✗ documents return to `PENDING` | The applicant re-uploads only what was flagged |
| D-13 | **Super admin can reset the counter** for a genuine case | Written to the audit trail |
| D-14 | **Move to another stage stays** | It is a routing action, not a decision, and is unaffected |
| D-15 | **`max_resubmissions = 3` means three correction rounds.** The counter increments on *resubmit*, not on reject | Confirmed 2026-08-25. The fourth reject closes the application. Supersedes the arithmetic implied by §4 step 5 and §5 as first written |
| D-16 | **All form fields are editable on resubmission; only ✗ documents are asked for again** | Supersedes the inferred field-unlocking in `public.types.ts`. No per-field flag is built — the reviewer's note says what is wrong, which is how GJEPC and the GST portal work. Also removes the "note with no ✗ document is a dead end" problem |
| D-17 | **Uniqueness is validated at correction time, not at approval** | A corrected GSTIN or PAN that collides with an existing `Members` row is refused while the applicant is still on the page, instead of failing the approval transaction weeks later |
| D-18 | **Super admin can reopen a closed application**, not merely reset the counter | Resolves the D-5 / D-13 tension. Reopening restores `RETURNED_FOR_CORRECTION`, zeroes the counter, issues a fresh token and re-sends the link. Fully audited |
| D-19 | **After a final rejection the applicant re-applies with the same email — no second account** | A new `MembershipApplication` is created on the existing `Users` + `Members` rows, counter back to 0, Stage 1. Both applications stay on record. Without this the email is locked out forever, since `PENDING_APPROVAL` blocks both login and re-registration |

---

## 3. Status model

```
                    ┌──────────────────────────────┐
                    │                              │
  SUBMITTED ──► UNDER_REVIEW ──Reject(under cap)──► RETURNED_FOR_CORRECTION
                    │  │                              │
                    │  └──Reject(at cap)──► REJECTED  │ resubmit (token link,
                    │                       (closed)  │  no login) → Stage 1
                    │                              ───┘
                    └──Approve final──► APPROVED ──► member code + invoice
                                                     + set-password email
                                                     → login possible
```

`RETURNED_FOR_CORRECTION` keeps its enum name — it is the applicant-facing label ("Action needed") that changes, not the database value. No enum migration is required.

---

## 4. Document verification rolls up into one Reject

The reviewer works the Documents panel first, then presses one button.

1. **Mark each document.** ✓ Verify or ✗ Reject. A ✗ demands a reason (already true).
2. **The panel keeps score.** Header reads `1 of 4 verified · 2 rejected · 1 waiting`.
3. **The Actions card reacts to that score.**
   - Any document ✗ → **Approve** disabled, with the reason named ("2 documents are rejected"); **Reject** is the emphasised action.
   - All required documents ✓ → **Approve** is primary.
   - Anything still `PENDING` → **Approve** disabled ("1 document is still waiting on you").
4. **One Reject click.** The dialog opens pre-filled with the ✗ documents and their reasons, plus a mandatory overall note.
5. **One transaction.** Application → `RETURNED_FOR_CORRECTION`, `resubmission_count + 1`, ✗ documents flagged for re-upload, approval request closed as `RETURNED`, audit rows written, notification queued.
6. **One email.** Overall note, the itemised document reasons, attempts remaining, and the resubmit link.

The rule that makes it coherent: **a document decision never leaves the building on its own.** The application-level decision is the only thing the applicant hears about.

---

## 5. Worked example — "Virali & Sons"

**Master setup.** `application.max_resubmissions = 3`. Stages: 1 Document verification (Admin, 48h) → 2 Committee review (Approver, 120h) → 3 Final approval (Super admin, 72h).

**Apply.** The public form is submitted with GST certificate, PAN document, Trade licence. One transaction writes `Users` (`PENDING_APPROVAL`, no password), `Members` (`DRAFT`), the addresses, the three `ApplicationDocument` rows (`PENDING`) and `MembershipApplication` (`SUBMITTED`, Stage 1, `resubmission_count = 0`). Email: "Application LGDGF/2026/0042 received — track or update it here: «token link»".

**Stage 1.** The admin marks Trade licence ✓, GST ✗ "certificate is blurred, the GSTIN is unreadable", PAN ✗ "name on the PAN does not match the trading name". The panel reads `1 of 3 verified · 2 rejected`. Approve is disabled. The admin clicks **Reject** once; the dialog already lists both reasons; the admin adds "Please re-upload both documents as clear scans."

**Result.** `RETURNED_FOR_CORRECTION`, `resubmission_count = 1`. Email carries the note, both document reasons, "2 of 3 attempts remaining", and the same link. No account is created. No password is set.

**Resubmit.** Virali & Sons opens the link — no login — and sees only the two flagged documents with their reasons. Trade licence is already verified and is not asked for again. Both are re-uploaded and submitted. The application returns to Stage 1 as `SUBMITTED`; the two documents are `PENDING` again; Trade licence stays `VERIFIED`.

**Stages 2 and 3.** Approve at Stage 1 moves it to Committee review; approve there moves it to Final approval. A reject at either stage behaves exactly as above and sends it back to Stage 1.

**Final approval.** In one transaction: member code `LGDGF/2026/0042` allocated, member `DRAFT → ACTIVE`, term opened, fee resolved and invoice raised, user `PENDING_APPROVAL → PENDING_VERIFICATION`, set-password email sent.

**Login.** Only now. The link sets the password, the user becomes `ACTIVE`, and the member portal opens.

**The other ending.** Had the third rejection landed, `resubmission_count` would have reached 3 — the application would be `REJECTED`, the token link dead, and the email would say the application is closed and a fresh one must be started.

---

## 6. Change list

### Database
- `ApplicationAccessToken` — `id`, `application_id` (FK, indexed), `token_hash` (unique), `expires_at`, `revoked_at`, `createdAt`. One live token per application; reissued on every reject.
- `ApplicationDocument.requires_reupload` (boolean, default false) — set by the reject transaction, cleared when a replacement is uploaded.
- No `ApplicationStatus` enum change.

### Backend
1. `application.service.ts` — reject resolves to `RETURNED_FOR_CORRECTION` or `REJECTED` by comparing `resubmission_count` against `application.max_resubmissions`; carries the document marks in the same transaction.
2. `approval.engine.ts` — `REVIEWER_TRANSITIONS` keeps both targets for reject; add a helper that decides which one the count implies.
3. Retire `/return`, `returnForCorrection`, `returnSchema`, `application.return` permission, `ACTION_FOR.return`, `REQUEST_STATUS_FOR.return`.
4. `rejectSchema` gains an optional `documents: [{ id, remarks }]` array for the rolled-up marks.
5. Server-side guard: approve fails if any required document is not `VERIFIED`.
6. New public routes — `GET /public/applications/:token`, `PATCH /public/applications/:token`, `POST /public/applications/:token/documents/:documentTypeCode`, `POST /public/applications/:token/submit`. Rate-limited, no auth, token hashed at rest.
7. Token issued on submit and reissued on every reject; revoked on `APPROVED` and on `REJECTED`.
8. `activation.service.ts` — the set-password email is sent here and nowhere earlier.
9. Notification templates — `application.rejected` carries the note, the itemised document reasons, attempts remaining and the link; `application.closed` for the cap case.
10. Super-admin counter reset endpoint, audited.
11. `ApprovalStages.allow_return` — dropped or repurposed; nothing reads it once Return is gone.

### Admin
12. `DecisionBar.tsx` — delete the Return button, `canReturn`, and the `'return'` branches of `messageFor` and `decide`. Approve disabled while documents are unverified, with the count named.
13. `DecisionDialog.tsx` — drop the `'return'` kind; the reject body lists the ✗ documents and their reasons above a mandatory note; the confirm copy states the consequence ("Attempt 1 of 3 — they can correct and resubmit" or "This is the final attempt — the application will close").
14. `DocumentsPanel.tsx` — remove the "rejecting a file does not return the application" copy; the header becomes the running score; ✗ reads as a mark, not a send.
15. `ApplicationQueue.tsx` — relabel the `RETURNED_FOR_CORRECTION` filter to "Rejected — awaiting resubmission"; keep the `resubmission_count` column and show it as `1 / 3`.
16. `ApplicationReview.tsx` — the resubmission chip shows attempts used against the cap.
17. Settings screen — expose `application.max_resubmissions` to super admin.
18. `status.ts` — reject-pending and reject-final read differently in the status map.

### Customer
19. New public resubmit page at the token URL — reason first, then only the flagged documents. No auth, no layout chrome that implies an account.
20. Remove `RETURNED_FOR_CORRECTION` from `EDITABLE_STATUSES` and delete the logged-in correction path in `ApplicationView.tsx`, `ApplicationStepper.tsx` and `ReviewStep.tsx`.
21. `nextActions.ts` and `applicationCopy.ts` — the returned-state copy points at the emailed link, not at a portal page.

---

## 7. Open questions

All resolved on 2026-08-25. Kept for the record.

- ~~**OQ-1 — Default for `application.max_resubmissions`.**~~ **Resolved 2026-08-25 — 3.** The seed changes from `0` (unlimited) to `3`. Super admin can still change it per association.
- ~~**OQ-2 — Token lifetime.**~~ **Resolved 2026-08-25 — no fixed expiry.** The token lives until the application reaches `APPROVED` or `REJECTED`, then is revoked. A "resend my link" path covers a lost email.
- ~~**OQ-3 — May the applicant edit form *fields* on resubmission, or only replace documents?**~~ **Resolved 2026-08-25 — both.** Form fields *and* documents are editable on resubmission, limited to what the reviewer flagged, because a PAN name mismatch may be a typo in the form rather than a bad scan.
- ~~**OQ-4 — Does a resubmission reset the stage SLA clock?**~~ **Resolved 2026-08-25 — yes.** A resubmission re-enters Stage 1 as new work with a fresh clock.
- ~~**OQ-5 — Applications already in `RETURNED_FOR_CORRECTION` when this ships.**~~ **Resolved 2026-08-25 — backfill.** A token is issued and the email resent, since those applicants currently have no way back in at all.
