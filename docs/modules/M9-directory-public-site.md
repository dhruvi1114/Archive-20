# M9 — Member Directory & Public Website

**Status:** PENDING · **Migration owner:** Agent A · **Blocking OQ:** OQ-7 (public or login-only; visible field set) · **Depends on:** M4 (active members exist)

## Goal
The federation has a credible public face, and members can find each other. Nothing private leaks.

## Agent A — backend + customer
- Migration: directory indexes (GIN full-text on company/legal name), `Members.directory_visible` if not already created in M2.
- `modules/directory`: public list/detail (ACTIVE + `directory_visible` only, restricted field set), member list/detail (richer field set), search + filters (category, city, business type), pagination.
- Public content endpoints: `/public/pages/:slug`, `/public/settings` (only `SystemSettings.is_public` rows).
- Customer screens C-01…C-05, C-28 + visibility toggle on C-29. Public pages SSR/ISR with proper metadata, sitemap, robots, OG tags.

## Agent B — admin support
- Admin toggle for global directory visibility + per-member override; `SystemSettings` entries for public page content; nothing else.

## Contracts frozen
Public field set vs member field set (explicit column allowlists, not "everything minus") · search behaviour · ISR revalidation window · SEO metadata rules.

## Self-test
`directory` suite: anonymous request returns only ACTIVE + visible members and **only** allowlisted fields (asserted key-by-key); a suspended/expired member disappears; a member with visibility off disappears; search matches company and legal name; SQL-injection string returns a normal empty result; pagination cap holds; public pages render without a token.

## Definition of done
- Field allowlist enforced server-side, not by the frontend.
- No email/phone/KYC field ever in an anonymous response unless OQ-7 explicitly permits it.
- Lighthouse ≥90 on performance and accessibility for public pages.

## Approval checklist
Directory public or login-only, and the exact visible field list (OQ-7) · homepage/about copy source · whether logos are shown publicly.
