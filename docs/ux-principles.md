# UX Principles

## 1. First principle

The database schema is not the information architecture. Screens exist because a person has a goal, not because a table exists. Two people use this platform for opposite reasons:

- **A member wants to stop wondering.** "Did it go through? What do I owe? When does it expire? What do I do next?"
- **An admin wants to clear a pile.** "What needs me right now, why, what can I do about it, and what happens when I do?"

Every screen is judged against one of those two sentences.

## 2. The four-line contract

Every important workflow must answer four questions:

| | Question |
|---|---|
| **Current state** | Where am I? |
| **Required action** | What must I do? |
| **Next step** | What happens next? |
| **Expected result** | What will I get? |

### This is a review rubric, NOT screen furniture

Read that again before designing anything. These four lines are what a reviewer asks *of* a screen. They are **never rendered as labelled panels**.

M1 shipped a login page with a bordered box reading "WHERE YOU ARE — You are signed out. / WHAT TO DO — Enter the email and password you registered with." That is a screen explaining in prose what its own form already shows, and it fails the very test it was quoting. It was removed.

**The interface answers the questions. Not a paragraph about the interface.**

| Question | Answered by |
|---|---|
| Current state | The page title, the status chip, the step marker in a stepper, the banner when something is wrong |
| Required action | The form itself, the field labels, and a submit button labelled with the verb ("Submit application", never "Submit") |
| Next step | A short line *at the point of action* where it is genuinely non-obvious — "We'll email you when the committee decides" under the submit button. Nowhere else |
| Expected result | What actually happens: the redirect, the toast that names the change, the new status on the record |

If a screen needs a paragraph to explain what it is for, the screen is wrong — rewrite the screen, do not add the paragraph.

The exception is genuine non-obviousness, and it earns **one sentence, inline, where the decision is made**: an approval's consequence in a confirm dialog, an expiry date next to a Pay button, "usually 2 working days" beside a pending status. Never a four-quadrant grid, never a "What this screen does" section.

## 3. Status is a sentence, not a badge

`PENDING` alone is a failure. `Pending — waiting for committee review since 2 days` is the requirement. Badges carry a tooltip/subline with the date and the actor being waited on.

## 4. State coverage — mandatory per screen

Loading (skeleton, not spinner-on-blank) · Empty (explains why it's empty + the one action that fills it) · Success (confirmation + next step) · Error (what failed, whether data was lost, how to retry) · Disabled (why it's disabled, inline) · Permission-restricted (hidden for members, "you don't have access" for admins) · Destructive confirmation (names the object and the consequence, requires typed confirmation for terminate/cancel-with-payments).

## 5. Error copy rules

Say what happened, why, and the fix. Never expose codes, table names or stack traces. Never blame the user.

**Errors are shown once.** Field errors sit next to the field, and that is normally the whole mechanism. On an invalid submit, focus moves to the first bad field.

A **form-level summary is off by default** and is turned on only for long or multi-step forms where a failing field can be scrolled out of view. M1 shipped it on a five-field signup: submitting an empty form produced five inline errors *and* a red panel restating all five in prose. The same information twice is not twice as clear.

**Required-field copy is one word.** A field labelled "Mobile number" showing "Enter a mobile number so we can reach you about your application." is telling the user what the label already told them. Empty required field → `Required`. Save the sentence for errors that carry information the user does not have: format rules ("Use a valid mobile number, e.g. +91 98250 12345"), server conflicts, or a consequence.

Bad: "Validation failed." Good: "GST number looks wrong — it should be 15 characters, like 24ABCDE1234F1Z5."

## 6. Progressive disclosure

Members see the minimum viable field set first; advanced/optional information is collapsed. The application form is a stepper with saved drafts, not a 60-field wall. Admins get density: tables, filters, bulk view, detail drawers — the opposite optimisation.

## 7. Never make a user re-enter what we know

Signup data pre-fills the application. Approved application data becomes the member profile (A-8). Renewal reuses the last term's data and asks only for confirmation and changes.

## 8. Money screens are explicit

Amounts always show currency and tax breakdown, due dates always show days remaining, and every payment CTA states what happens after payment ("Membership activates immediately; receipt is emailed").

## 9. Accessibility & responsiveness baseline

WCAG 2.1 AA contrast · full keyboard operation · visible focus ring · labels tied to inputs · `aria-live` on async state changes · 44px touch targets · member portal fully responsive (phones are the reality for Surat trade members) · admin portal targets ≥1280px with a usable ≥768px fallback.

## 10. Performance as UX

Skeletons for lists, optimistic UI only where the server can't refuse (never for approvals or payments), list pages paginated at 20, no full-page reload after an action — refresh the row and show a toast that names the change.

## 11. Separation of Customer and Admin UX

Two different products, deliberately. Members never see internal vocabulary ("stage 2 of workflow MEMBERSHIP_APPROVAL", "ApprovalRequest #442"); they see "Committee review". Admins never get consumer-style empty dashboards; they get a work queue as the landing page.
