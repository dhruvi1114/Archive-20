# One Site for Members — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Signing in stops replacing the website. A member keeps every public page they had as a visitor, and the member area becomes something they reach from an account menu rather than somewhere they are moved to.

**Architecture:** Two shells stay, and that is deliberate — see Constraint 1. What changes is that both shells carry the same primary navigation and the same account menu, so the two halves read as one site from the visitor's side even though they are styled by two systems. The public header gains an account menu when a session exists; the member top bar gains the public nav so a member can get back to the website from any member screen.

**Tech Stack:** Next.js 14 App Router, TypeScript, Tailwind (member area), the scoped `site.css` (public area), redux-persist for the session.

**Spec:** this document. The decision it reconciles is recorded in
[`docs/directory-module-summary.md`](../../directory-module-summary.md).

---

## Global Constraints

Read these before starting any task. Two of them are the reason this plan looks
the way it does.

1. **Member screens cannot move inside `.da`.** The public stylesheet is
   light-only and carries resets — `a { color: inherit }`, `ul { list-style:
   none }`, `h1..h3 { margin: 0 }` — that would silently restyle every member
   screen, and the member app supports dark mode which `.da` does not. Any
   approach that wraps the member area in the public shell is out of scope and
   should be raised, not attempted.

2. **The directory is members-only, and stays advertised.**
   `docs/directory-module-summary.md` records the gating: no public audience, no
   public route, no sitemap entry, and the logo endpoint closed because a public
   logo URL would disclose that a named company is a member. None of that
   changes here.

   What stays is the **link**, and what a stranger meets is a door rather than a
   redirect. Directory remains in the public navigation for everyone, because it
   is one of the things membership buys and a visitor who cannot see it
   advertised has no reason to want it.

   Three states, and the first is new (Task 6):

   | Who | `/directory` shows |
   |---|---|
   | Signed out | A gate: what the directory is, **Log in** and **Become a Member** |
   | Signed in, membership not active | The existing renewal lock screen |
   | Signed in, active member | The directory |

   A visible link to a gated route is not a public route: no member data is
   rendered for a stranger, and the page stays out of every sitemap.

3. **The session is client-side only.** The server cannot know who is signed in,
   so any header that renders a name or an account menu must hold it back until
   after hydration — the pattern `MemberShell` already uses with `mounted`.
   Rendering it during SSR makes the server emit one tree and the client
   another, and React throws the whole thing away and re-renders the root.

4. **`aria-current` and focus behaviour are part of the deliverable**, not
   polish. The account menu is a real menu: it opens on click, closes on Escape,
   closes on outside click, and returns focus to its trigger.

5. **Verification:** `npm run typecheck && npm run lint && npm run verify:home`
   from `customer/`, plus a build into an isolated directory —
   `NEXT_DIST_DIR=.next-verify npm run build` — so a running dev server's
   `.next` is never overwritten. Revert `tsconfig.json` afterwards; Next rewrites
   it during a build with a custom dist dir.

6. **Do not touch running dev servers**, and do not delete `.next`.

---

## What changes, at a glance

| Page | Logged out today | Logged in today | Logged in after |
|---|---|---|---|
| `/`, `/about`, `/membership`, `/events`, `/news`, `/contact` | public site | public site | **unchanged** — public site |
| `/directory` | bounced to `/login` with no explanation | member shell | **a gate page** signed out; the directory signed in |
| `/dashboard`, `/profile`, `/invoices`, `/events/my`, `/notices`, `/application`, `/settings`, `/notifications` | bounced to login | member shell | member shell, reachable from the account menu, with the public nav in its top bar |

The header is the whole change:

```
Logged out:  Home About Membership Events News Directory Contact   Member Login  [Become a Member]
Logged in:   Home About Membership Events News Directory Contact   [Dhruvi Barot ▾]
                                                              ├── Dashboard
                                                              ├── Application & membership
                                                              ├── Profile
                                                              ├── Billing
                                                              ├── My registrations
                                                              ├── Notices
                                                              ├── Member directory
                                                              ├── ──────────────
                                                              ├── Settings
                                                              └── Log out
```

---

## File Structure

### Create

| File | Responsibility |
|---|---|
| `src/constants/accountNav.ts` | The account menu's items, in one list both shells read |
| `src/components/site/AccountMenu.tsx` | The menu itself: trigger, panel, keyboard behaviour |
| `src/components/site/useSignOut.ts` | Sign-out shared by both shells |

### Modify

| File | Change |
|---|---|
| `src/constants/homeContent.ts` | Unchanged by this plan — see Task 3 Step 1 |
| `src/components/site/SiteHeader.tsx` | Account menu when a session exists, login/join when not |
| `src/components/site/site.css` | Styles for the menu |
| `src/components/layout/MemberShell.tsx` | Public nav in the top bar; account menu replaces the bare name |
| `src/constants/navigation.ts` | The duplicated Directory entry removed |
| `src/components/home/MembersMarquee.tsx` | Deleted — see Task 5 |
| `src/app/(public)/page.tsx` | The marquee comes off the homepage |

### Leave alone

`MemberRouteGuard`, every page under `(member)`, the member side nav, and the
whole of `site.css` outside the block Task 2 adds. This plan changes navigation,
not screens.

---

## Task 1: One list of account destinations

**Files:**
- Create: `src/constants/accountNav.ts`
- Modify: `src/constants/navigation.ts`

**Interfaces:**
- Produces `ACCOUNT_NAV: NavItem[]` and `ACCOUNT_UTILITY_NAV: NavItem[]`, consumed by Tasks 2 and 4.

- [ ] **Step 1: Write `src/constants/accountNav.ts`**

```ts
import type { NavItem } from './navigation';
import { MEMBER_NAV, MEMBER_UTILITY_NAV } from './navigation';

/**
 * What sits behind the account menu.
 *
 * Deliberately derived from `MEMBER_NAV` rather than retyped beside it. These
 * are the same destinations the member side nav lists, and a second hand-written
 * copy is how the menu and the sidebar start disagreeing about what a member has.
 */
export const ACCOUNT_NAV: NavItem[] = MEMBER_NAV;

/** Settings and notifications, below a rule. Not primary destinations. */
export const ACCOUNT_UTILITY_NAV: NavItem[] = MEMBER_UTILITY_NAV;
```

- [ ] **Step 2: Remove the duplicated Directory entry**

`src/constants/navigation.ts` lists Directory twice — once at the end of
`MEMBER_NAV` with the description "Find other members", and once earlier with
"Find and contact other members". Delete the **later, shorter** one:

```ts
  {
    href: '/directory',
    label: 'Directory',
    description: 'Find other members',
  },
```

The earlier entry is the one to keep: it carries the `match` property the
sidebar's `isActive` needs, and the comment above it explains why the entry is
shown to every signed-in member rather than only to active ones.

- [ ] **Step 3: Verify the seven-item rule holds**

```bash
cd customer && grep -c "href: '/" src/constants/navigation.ts
```

Then read `MEMBER_NAV` and confirm it now has exactly seven entries, which is
what the file's own comment claims and what `information-architecture.md` §1
requires. If it has eight, another duplicate slipped in.

- [ ] **Step 4: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

- [ ] **Step 5: Commit**

```bash
cd customer && git add src/constants
git commit -m "fix(nav): one Directory entry, and one list of account destinations"
```

---

## Task 2: The account menu

**Files:**
- Create: `src/components/site/useSignOut.ts`
- Create: `src/components/site/AccountMenu.tsx`
- Modify: `src/components/site/site.css`

**Interfaces:**
- Consumes `ACCOUNT_NAV`, `ACCOUNT_UTILITY_NAV` (Task 1).
- Produces `<AccountMenu variant="site" | "member" />`, consumed by Tasks 3 and 4.

- [ ] **Step 1: Find how the app signs out today**

```bash
cd customer && grep -rn "clearAuthState\|AuthService.logout" src --include=*.tsx --include=*.ts | grep -v node_modules | head
```

Write `useSignOut.ts` around whatever that search finds, rather than inventing a
second sign-out. It must call the same service and dispatch the same action the
existing sign-out does, then send the visitor to `/`.

- [ ] **Step 2: Write `AccountMenu.tsx`**

A button that opens a panel. The requirements, all of which are testable by
hand and none of which are optional:

- renders nothing at all until `mounted` (Constraint 3) — before that, the
  caller's logged-out markup stands
- `aria-haspopup="menu"`, `aria-expanded`, and `aria-controls` on the trigger
- the panel is `role="menu"`, its items `role="menuitem"`
- Escape closes it and returns focus to the trigger
- a click outside closes it
- a route change closes it
- the two utility items sit below a rule
- Log out is last, and is a `<button>` — it performs an action rather than
  navigating

`variant` decides only the class names, so the same component can sit in the
public header (`.da`-scoped classes) and in the member top bar (Tailwind
classes). It must not fork its behaviour on the variant.

- [ ] **Step 3: Add the public-side styles to `site.css`**

Put them in the Header block, next to `.member-login`. The panel needs
`position: absolute`, a `z-index` above the sticky header's `100`, the page's
`--da-radius-m`, a border in `--da-border`, and `--da-bg`. Items are
`--da-fs-supporting`. Do not invent a colour: every value comes from the `--da-*`
set already defined at the top of the file.

- [ ] **Step 4: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

- [ ] **Step 5: Commit**

```bash
cd customer && git add src/components/site
git commit -m "feat(site): account menu"
```

---

## Task 3: The public header knows about the session

**Files:**
- Modify: `src/components/site/SiteHeader.tsx`
- Modify: `src/constants/homeContent.ts`

- [ ] **Step 1: Leave the Directory links exactly where they are**

`SITE_NAV`, the footer's "Member Directory" and the homepage's "Explore Member
Directory" all stay. This step exists to record that it is a decision rather
than an oversight: the directory is one of the things membership buys, and a
visitor who never sees it advertised has no reason to want it. Signed out, the
link lands on the sign-in screen and returns to the directory afterwards, which
`MemberRouteGuard` already does.

Nothing to change here. Move to Step 2.

- [ ] **Step 2: Swap the header's right-hand side on the session**

`SiteHeader` becomes session-aware: read the token from the store and
`useRehydrated`, and hold the swap back until rehydrated (Constraint 3) so a
signed-in member does not see "Member Login" flash before the menu appears.

Logged out, nothing changes. Logged in, the two links are replaced by
`<AccountMenu variant="site" />`.

The mobile panel gets the same treatment: the account destinations replace
"Become a Member"/"Member Login" for a signed-in member.

- [ ] **Step 3: Verify by hand**

Open `/` signed out, then sign in and return to `/`:
- signed out: Member Login + Become a Member, and Directory still in the nav
- signed out, clicking Directory reaches the gate page from Task 6 — not the
  sign-in screen
- signed in: the account menu, and every public page still reachable
- the menu opens, closes on Escape, closes on an outside click, and each item
  navigates to the right member page

- [ ] **Step 4: Verify**

```bash
cd customer && npm run typecheck && npm run lint && npm run verify:home
```

- [ ] **Step 5: Commit**

```bash
cd customer && git add src/components/site
git commit -m "feat(site): the public header carries the member's account menu"
```

---

## Task 4: A member can get back to the website

**Files:**
- Modify: `src/components/layout/MemberShell.tsx`

- [ ] **Step 1: Put the public nav in the member top bar**

The top bar currently holds a logo, a theme toggle, a bell, a cog and a name.
Add the `SITE_NAV` links between the logo and the icons, styled with the member
app's own Tailwind classes — not `site.css`, which does not reach here
(Constraint 1).

This is the half of the change that makes the site continuous: from Dashboard, a
member can click Events and land on the public events page, which already shows
them member pricing and members-only events.

Below the `lg` breakpoint the links move into the existing mobile nav sheet
rather than crowding the bar.

- [ ] **Step 2: Replace the bare name with the account menu**

The name currently renders as plain text. Swap it for
`<AccountMenu variant="member" />`, which gives a member the same control in both
halves of the site — and gives them a Log out that, today, the shell does not
offer at all.

Keep the bell and the cog: they are one-click shortcuts to two of the menu's own
items, which is worth the duplication on a screen a member lives in.

- [ ] **Step 3: Verify by hand**

Sign in and open `/dashboard`:
- the public nav is in the top bar and each link leaves for the public site
- the account menu opens and Log out returns to `/` signed out
- the left member nav is unchanged, and lists Directory exactly once
- the theme toggle still works, and the member area is still dark-mode capable

- [ ] **Step 4: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

- [ ] **Step 5: Commit**

```bash
cd customer && git add src/components/layout/MemberShell.tsx
git commit -m "feat(member): the member area carries the site's own navigation"
```

---

## Task 5: Retire the homepage member wall

**Files:**
- Delete: `src/components/home/MembersMarquee.tsx`
- Modify: `src/app/(public)/page.tsx`
- Modify: `src/components/site/site.css`
- Modify: `src/services/SiteService.ts`

The marquee is already disabled — its body is commented out, and the backend no
longer returns `featured_members`. This task removes the remains rather than
leaving a component that renders nothing and a block of commented-out code that
will not survive contact with the next person to read it.

- [ ] **Step 1: Confirm the decision still holds**

```bash
cd "/Users/sarvadhisolution/Documents/Archive 20" && grep -n -i "marquee\|logo" docs/directory-module-summary.md | head
```

Expected: the summary says a public logo URL discloses membership, and the
homepage name marquee is dropped. **If it does not say that, stop** — the
component is disabled for a reason that has changed, and deleting it is then the
wrong move.

- [ ] **Step 2: Remove it**

Delete the component, its `<MembersMarquee />` line and import in
`(public)/page.tsx`, the `.marquee*` and `.logo-cell*` rules in `site.css`, and
the commented-out `featured_members`/`SiteFeaturedMember` remains in
`SiteService.ts`.

Leave the "Our Partners" section alone. It is static content and has nothing to
do with the directory.

- [ ] **Step 3: Verify nothing still refers to it**

```bash
cd customer && grep -rn "MembersMarquee\|featured_members\|logo-cell\|marquee" src | grep -v node_modules
```

Expected: no output.

- [ ] **Step 4: Verify**

```bash
cd customer && npm run typecheck && npm run lint && npm run verify:home
NEXT_DIST_DIR=.next-verify npm run build && git checkout tsconfig.json && rm -rf .next-verify
```

- [ ] **Step 5: Commit**

```bash
cd customer && git add -A
git commit -m "chore(home): remove the retired member wall"
```

---

## Task 6: A door on the directory, not a redirect

**Files:**
- Create: `src/components/member/DirectoryGate.tsx`
- Modify: `src/app/(member)/directory/page.tsx`
- Modify: `src/components/auth/MemberRouteGuard.tsx` *(only if it cannot be avoided — see Step 2)*

Today a signed-out visitor who clicks Directory is thrown at `/login` with no
idea why. That is the worst version of a gate: it asks for a password without
saying what the password is for, and it says nothing at all to the visitor who
has no account and is exactly the person the association wants to reach.

- [ ] **Step 1: Read how the renewal lock does it**

```bash
cd customer && grep -rln "membership has expired\|Renew membership" src
```

The directory already has a lock screen for a member whose membership lapsed. The
gate for a stranger is the same idea one step earlier, and should look like its
sibling rather than like a new invention — read it before writing.

- [ ] **Step 2: Keep the guard out of it**

`MemberRouteGuard` wraps the whole `(member)` tree and redirects anyone without
a session. The gate has to render *instead of* that redirect, for this route
only.

Prefer the change that does not touch the guard: if `(member)/directory/page.tsx`
can render the gate itself for a signed-out visitor, the guard stays as it is for
every other member page. Only if the guard's redirect fires first — check by
loading `/directory` signed out — add an opt-out to it, and add it as a property
of the route rather than a hard-coded path list.

Whatever the mechanism, no directory data may be fetched for a signed-out
visitor. The gate is a page about membership; it is not the directory with the
rows hidden.

- [ ] **Step 3: Write the gate**

What it says, in the order `ux-principles.md` asks for:
- **Current state** — the member directory is open to members of the association
- **What it is** — search members by name, category and location, and contact
  them directly
- **Required action** — two buttons: **Log in** (primary) and **Become a Member**
- **Next step** — signing in returns here, to the directory

Log in must carry the return path, so signing in from the gate lands back on
`/directory`. `loginWithNext` in `src/constants/routes.ts` is what already builds
that URL.

- [ ] **Step 4: Verify by hand**

- signed out, `/directory` shows the gate — no redirect, no member rows, no
  network call for directory data (check the Network tab)
- Log in on the gate reaches sign-in, and signing in arrives at `/directory`
- Become a Member reaches `/signup`
- signed in with an active membership, `/directory` is unchanged
- signed in without one, the renewal lock is unchanged
- every other member page still redirects to sign-in when signed out

- [ ] **Step 5: Verify**

```bash
cd customer && npm run typecheck && npm run lint
```

- [ ] **Step 6: Commit**

```bash
cd customer && git add -A
git commit -m "feat(directory): a door for visitors, not a redirect"
```

---

## Task 7: Walk both halves

**Files:** none — this is the acceptance pass.

- [ ] Signed out, every public page loads: `/`, `/about`, `/membership`,
      `/events`, `/news`, `/contact`
- [ ] Signed out, Directory is in the nav, and clicking it shows the gate page
      with both ways in — never a bare redirect, and never any member data
- [ ] From the gate, Log in returns to `/directory` after signing in
- [ ] A signed-in member with no active membership still meets the renewal lock
- [ ] Signed out, `/dashboard` still redirects to `/login` and returns there
      after signing in
- [ ] Signed in, every one of those public pages **still loads**, in the public
      design — this is the whole point of the change
- [ ] Signed in, `/events` shows member pricing, as it did before
- [ ] The account menu lists every member page, from both shells
- [ ] Log out works from both shells and lands on `/`
- [ ] The member area still toggles dark mode; the public site does not follow it
- [ ] Keyboard: the menu opens, Escape closes it, focus returns to the trigger,
      and Tab never lands inside a closed panel

---

## Self-Review Notes

- The directory stays gated and stays advertised. The route is not made public;
  only the link to it remains, and the guard already turns a signed-out click
  into a sign-in that returns to the directory.
- Constraint 1 is why Tasks 3 and 4 both exist. One header change would have done
  it if the member screens could adopt `.da`, and they cannot.
- `MemberRouteGuard` is untouched. Nothing here changes who may open a member
  page — only how they get to it.
- Task 5 is separable. If the marquee decision is reversed, drop that task; the
  other five stand on their own.
- Not in scope, and worth saying so: restyling the member screens to match the
  public design. That is a much larger piece of work and this plan does not
  pretend to have started it.
