# Approval Stage On/Off Switch — Specification

**Date:** 2026-09-09
**Status:** Agreed 2026-09-09. Open questions: none.
**Affects:** `docs/approval-workflow.md` §2b (the three-stage default), `docs/specs/2026-08-25-reject-resubmit-flow.md` **D-11** (resubmission re-enters at Stage 1 — now the first *active* stage).

---

## 1. Why

The membership workflow ships with three stages: Document verification (ADMIN, 48h) → Committee review (APPROVER, 120h) → Final approval (SUPER_ADMIN, 72h).

Two of them are not real. No committee meets, so Committee review is a rubber stamp that adds a 120-hour SLA and teaches reviewers to click through a step that decides nothing. And a super admin is currently the only person deciding anything, so splitting the work across a maker stage and a checker stage records one person as both — a control that looks real in the audit log while being none.

The association wants **one step: Final approval**, owned by SUPER_ADMIN.

It does **not** want the other two stages deleted. Committee review carries decision history, and the day a second person joins to check documents, the two-stage maker-checker flow must come back without a migration.

So the stages get an on/off switch.

---

## 2. Decisions taken

| # | Decision | Consequence |
|---|---|---|
| D-1 | **A stage can be switched off without being deleted.** New `ApprovalStage.is_active`, default `true` | One migration. No row is removed, no history is touched |
| D-2 | **The target configuration is one active stage: Final approval.** Document verification and Committee review are switched off | Seeded, so the decision is in code and reviewable — not typed into a database once |
| D-3 | **An inactive stage is skipped, not renumbered.** `sequence` values stay 1, 2, 3 | Turning a stage back on restores its position exactly. Renumbering would make the switch destructive, which is the thing this spec exists to avoid |
| D-4 | **An application parked on an inactive stage stays valid and moves forward.** Approving it advances to the next *active* stage, or approves outright if there is none | APP2026030024 sits on Committee review today. It must not get stuck, and it must not need a data migration |
| D-5 | **"First stage" means first *active* stage** everywhere: new applications, resubmissions, reopened applications | All three paths already funnel through `engine.stageForResubmission`, so this is one function |
| D-6 | **The document check is unchanged and still applies.** Approve stays blocked while any required document is unverified | Verified: the check runs on every approve at `application.service.ts:478`, not at a named stage. Switching off Document verification does **not** make document verification optional. This is what makes D-2 safe |
| D-7 | **Screens count position within the active list, never the raw `sequence`** | Today `ApplicationReview.tsx:94` prints `Stage {sequence} of {stages.length}`. With a gap that reads "Stage 3 of 2" |
| D-8 | **"What happens next" is the next active stage, not `sequence + 1`** | `DecisionDialog.tsx:123` and `DecisionBar.tsx:114` do sequence arithmetic. With stages 1 and 2 off, `1 + 1` finds a stage that is switched off |
| D-9 | **Move to another stage offers active stages only**, and the server refuses an inactive target | A routing action must not park an application somewhere nobody is looking |
| D-10 | **The workflow settings screen shows inactive stages, marked Off** | The screen exists to answer "why is this application not in my queue?" (`Workflow.tsx` doc comment). Hiding the switched-off stages deletes the answer |
| D-11 | **At least one stage must stay active.** A workflow with none is a conflict, as an empty one already is | Reuses the existing `application.workflowHasNoStages` error |
| D-12 | **The APPROVER role is not touched.** Its holders simply have an empty queue | Deleting it is a separate decision, and `approver_role_id` is `onDelete: Restrict` anyway |
| D-13 | **No stage editor UI.** The switch is set by seed | ADR-011 parked the workflow builder to M10 and that stands. This spec does not un-park it |

---

## 3. Why not the alternatives

**Delete the Committee review row.** The database refuses it. `ApprovalRequest.current_stage_id` and `ApprovalAction.stage_id` are both `onDelete: Restrict` (`application.prisma:554`, `:603`), so the row is locked by any application sitting there and by every decision ever recorded there. Deleting would also throw a CONFLICT for in-flight applications — `resolveApproval` raises `application.stageNotInWorkflow` when a live stage vanishes (`approval.engine.ts:108`), which is correct behaviour and exactly why deletion is wrong.

**Comment the stage out of the seed.** Does nothing. The seed only upserts (`approvalWorkflow.ts:68`); it never deletes, so the database keeps the stage and the app keeps using it.

**Renumber sequences to close the gap.** Makes the switch one-way. Turning Committee review back on would need a fresh migration to re-open the gap, and any historical `ApprovalAction` pointing at the old position becomes misleading.

---

## 4. Data model

One column on `ApprovalStage`:

```prisma
/// Whether this stage takes part in the flow. An inactive stage is skipped —
/// never deleted — so its decision history stays readable and turning it back
/// on restores its position. `ApprovalWorkflow` carries the same flag for the
/// same reason.
is_active Boolean @default(true)
```

Migration `20260909060000_approval_stage_is_active`:

- `ALTER TABLE "ApprovalStages" ADD COLUMN "is_active" BOOLEAN NOT NULL DEFAULT true;`
- Partial index on `(workflow_id, sequence) WHERE is_active` is **not** added — the table holds three rows.

The migration adds the column only. It does **not** switch any stage off: that is the seed's job (D-2), so the configuration is reviewable in code and re-runnable.

---

## 5. Backend changes

### 5.1 `prisma/seed/approvalWorkflow.ts`

`StageSeed` gains `isActive?: boolean`. `MEMBERSHIP_STAGES` becomes:

| seq | name | role | SLA | active |
|---|---|---|---|---|
| 1 | Document verification | ADMIN | 48h | **false** |
| 2 | Committee review | APPROVER | 120h | **false** |
| 3 | Final approval | SUPER_ADMIN | 72h | true (`is_final`) |

Both the `create` and `update` branches of the `approvalStage.upsert` write `is_active`, so re-seeding is still idempotent and a re-run re-asserts the intended configuration. A comment records why each stage is off and what turning it back on means.

`PROFILE_CHANGE_STAGES` is untouched.

### 5.2 `src/modules/application/approval.engine.ts`

Two functions change; both keep their current signature.

**`resolveApproval(stages, currentStageId)`**
- Find the current stage among **all** stages, active or not — an application parked on a switched-off stage must still resolve (D-4). Keep the existing `stageNotInWorkflow` throw for a stage that is genuinely absent.
- Advance to the next stage after it that is **active**.
- Return `isFinal` when the current stage is `is_final`, or when no active stage follows it.

**`stageForResubmission(stages)`**
- Return the first **active** stage by sequence.
- Throw the existing `application.workflowHasNoStages` when none is active (D-11).

A third, new helper — `assertStageSelectable(stages, stageId)` — backs D-9: the reassign target must exist and be active, else `application.stageNotInWorkflow`.

### 5.3 `src/modules/application/application.service.ts`

- `decide(...)`, reassign branch (`:509`): replace the raw `stages.find(...)` with `assertStageSelectable`, so a direct POST cannot park an application on an inactive stage.
- `getWorkflow()` (`:753`): unchanged in shape. It returns every stage including inactive ones, now carrying `is_active`, because the settings screen must show them (D-10) and the review screen needs the full list to resolve a parked application's name.

No change to `register.service.ts` or `public.service.ts` — all three call `stageForResubmission` (D-5).

### 5.4 Repository

`findActiveWorkflow` keeps returning all stages ordered by sequence. Filtering happens in the engine, not the query, so one code path decides what "active" means.

---

## 6. Admin changes

`ApprovalStage` in `services/applicationsService.ts` gains `is_active: boolean`.

| File | Change |
|---|---|
| `pages/applications/ApplicationReview.tsx` (`StageTrail`, :75) | Render active stages only. Label counts position in that list, not `sequence` (D-7). An application parked on an inactive stage is the exception: show that stage too, marked `current`, so the reviewer can see where it actually is |
| `pages/applications/DecisionBar.tsx` (:114) | "What happens next" = next active stage, not `sequence + 1` (D-8) |
| `pages/applications/DecisionDialog.tsx` (:123, :348) | Same for its copy; the reassign `options` list drops inactive stages (D-9) |
| `pages/applications/ApplicationQueue.tsx` (:443) | **No change.** The Stage filter lists every stage, active or not — it searches history, and rows parked on a switched-off stage must stay findable. A filter answers "where is this row", not "where may I send it" |
| `pages/settings/Workflow.tsx` (:80) | Show every stage; inactive ones muted with an "Off" `Badge` and a line saying they are skipped (D-10) |

Per `association-admin-ui`: the Off marker is a `Badge`, not a hand-built pill, and no page sets a colour.

---

## 7. What the user sees after this ships

**Review screen** (`/applications/:id`): a one-step trail — "Stage 1 of 1: Final approval · Super admin decides · 72h target". The documents card is unchanged, and Approve stays disabled until every required document is verified.

**APP2026030004** (parked on Document verification, switched off) and **APP2026030024** (parked on Committee review, switched off): both still show their parked stage as current, and both take **two** approvals to finish. The first advances them to Final approval — the next active stage after their position — and the second approves them.

That is D-4 working as specified, not a defect: an application mid-flow keeps the stages ahead of it. Only applications that *start* after this ships get the one-step path. Nothing about either row is migrated, and neither gets stuck.

*(An earlier draft of this section claimed both would go straight to APPROVED. That was wrong — Final approval is active and does follow them. The rule in §5.2 is authoritative; this paragraph now matches it, and the service test pins the behaviour.)*

**A new application:** starts at Final approval.

**A rejected-then-resubmitted application:** re-enters at Final approval — the first active stage (D-5, amending D-11).

**Workflow settings** (`/settings/workflow`): all three stages listed, the first two marked Off, so anyone asking why there is only one step gets the answer on the screen built to give it.

---

## 8. Turning maker-checker back on

Set `isActive: true` on Document verification in the seed and re-run it. Two steps return, sequences unchanged, all committee history still readable. No migration, no code change.

---

## 9. Testing

**Engine (unit).** One active stage approves outright. Two active with a gap advances 1 → 3, not 1 → 2. An application on an inactive stage advances to the next active one, and approves when none follows. `stageForResubmission` skips inactive stages and throws when none is active. `assertStageSelectable` refuses an inactive target.

**Service (integration).** Approve at the single active stage sets APPROVED and closes the request. Approve is still refused while a required document is unverified — the case that makes D-2 safe, so it is tested with Document verification switched off. Reassign to an inactive stage returns CONFLICT.

**Seed.** Re-running is idempotent and re-asserts the flags.

**Admin.** `StageTrail` renders one step from a three-stage workflow with two off, and still renders a parked inactive stage as current.

**Manual, against the running app.** Approve APP2026030024 (parked on Committee review) and confirm it advances to Final approval rather than erroring, then approve again and confirm it reaches APPROVED.

---

## 10. Out of scope

- A UI for switching stages on and off — ADR-011, M10 (D-13).
- Deleting or retiring the APPROVER role (D-12).
- Any change to rejection, resubmission limits, or the document gate.
