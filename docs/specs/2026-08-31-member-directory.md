# Member Directory — Design Specification

**Date:** 2026-08-31
**Module:** M9 (the directory half; the News half is already built)
**Status:** Design agreed 2026-08-31. Awaiting review before implementation.
**Answers:** D1 / OQ-7 — **members-only (Option B1)**. No public view of any kind.
**Depends on:** M3 (member records exist), M4 (members reach `ACTIVE`), M2 (categories), M5 (payment is what makes a member `ACTIVE`).

---

## 1. Why

A federation exists partly so its members can find each other. Today the platform holds 142 member records and offers no way to browse them. `customer/src/app/(public)/directory/page.tsx` is a placeholder.

The directory is a **membership benefit**, not a marketing page. It is the thing a member gets for paying, and the clearest answer to "what do I get for ₹25,000?"

Everything below follows from one decision: who is allowed to open it at all.

---

## 2. The decision

**The directory is members-only.** There is no anonymous view. No public list, no public profile, no public search, no sitemap entry, no Google indexing. A visitor without an account gets a sign-in prompt and nothing else — not even company names.

### 2.1 Why not a public directory

A public list with gated contact details was considered and rejected. It would have given the association SEO and a public face, and the locked contact block would have advertised membership to passers-by.

It was rejected because it answers the wrong question. The two real comparables in Indian export bodies diverge, and they diverge on purpose rather than on principle:

| | GJEPC | FIEO |
|---|---|---|
| Directory serves | Members finding each other | Overseas buyers finding Indian exporters |
| Therefore | Behind login, with per-profile view permissions | Public, searchable by anyone |

This association's directory serves the first purpose. It is a networking tool for members, not a trade-promotion channel for foreign buyers. Gating it matches the purpose, and matches GJEPC, the closest comparable body.

### 2.2 The gate is `ACTIVE`, not "logged in"

This is the single most important rule in the module.

Holding a login is not the same as being a member. Several kinds of people hold logins:

| Who | `Members.status` | Can open the directory |
|---|---|---|
| Paid, current member (owner or invited colleague) | `ACTIVE` | **Yes** |
| Signed up, application not yet approved | `DRAFT` / `PENDING` | No |
| Approved but first invoice unpaid | `PENDING` | No |
| Membership lapsed or withdrawn | `EXPIRED` / `SUSPENDED` / `TERMINATED` | No |
| Association staff | n/a — admin user | Not via the directory; they use the Members screen |

If the gate were merely "is there a valid token", anyone could complete the two-minute signup form and take 142 phone numbers without paying, and every lapsed member would keep the benefit forever.

A non-`ACTIVE` user receives **no company data at all** — a `403` carrying a reason code, never a partial list. The frontend turns that reason into the right prompt:

| Reason code | Prompt |
|---|---|
| `NO_MEMBERSHIP` | "The member directory is for members." · `[Become a member]` |
| `PAYMENT_PENDING` | "Your membership is pending payment." · invoice number and amount · `[Pay now]` |
| `EXPIRED` | "Your membership expired on 31 Mar 2026." · `[Renew]` |
| `SUSPENDED` | "Your membership is currently suspended. Please contact the association." |

That lock screen is not an obstacle. It is the clearest statement of value the platform makes, and it sits directly in front of a payment button.

### 2.3 What this decision removes

Choosing B1 over a public directory removes work and removes an entire class of defect:

| | Public option | **B1** |
|---|---|---|
| Routers | 2 — public and member | **1** |
| Field allowlists | 2 | **1** |
| SEO, sitemap, OG tags, ISR | required | **none** |
| Server-rendering for crawlers | required | **not needed** |
| Customer route location | `(public)/directory` | `(member)/directory` |
| Risk of a phone number in a public response | the principal risk | **structurally impossible** |

Under a public design, the main hazard was accidentally serialising a contact field into an anonymous response. Under B1 there is no anonymous response, so that hazard does not exist.

---

## 3. Two independent questions

The module answers two questions that are easy to conflate. They use overlapping inputs and must not be collapsed.

**"May I look?"** — decided solely by the viewer's own company status.

**"Am I listed?"** — decided by three switches on the listed company. All three must be true:

| # | Switch | Column / source | Controlled by | Example |
|---|---|---|---|---|
| 1 | Directory is enabled | `SystemSettings` key `directory.enabled` | Association | Turned off during a data cleanup |
| 2 | Membership is current | `Members.status = ACTIVE` | The system, off payment and renewal | Kiran Traders does not renew on 31 Mar → gone that night |
| 3 | The member consents | `Members.directory_visible` | The member, on their profile | Rakesh unticks "list my company" → gone, still a paid member |

The consequence worth stating plainly: **a member who opts out can still search the directory.** Looking and being listed are separate. Opting out is not a resignation from the benefit.

Switch 2 is what makes the directory trustworthy across years — a company that stopped paying can never quietly remain listed, because no human step is involved in removing it.

Switch 3 already exists on the model, defaulting to `true`, with `@@index([directory_visible, status])` already applied.

---

## 4. Worked example

**Shreeji Exports Pvt Ltd** — Ahmedabad, spices and agri-commodities, `ACTIVE`, listed.

```
company_name       Shreeji Exports Pvt Ltd
legal_name         Shreeji Overseas Trading Pvt Ltd
member_code        LGDGF/2026/0042
status             ACTIVE
directory_visible  true
website            https://shreejiexports.in
about              Spice and agri-commodity exporters since 1998.
gst_number         24AABCS1234F1Z5      ← never leaves the admin app
pan_number         AABCS1234F           ← never leaves the admin app
iec_code           0398012345           ← never leaves the admin app
address            Ahmedabad, Gujarat, India, 380009   (primary)
contact            Rakesh Patel, Director,
                   rakesh@shreejiexports.in, +91 98250 12345   (primary)
categories         Spices, Agri Commodities
```

### 4.1 A stranger from Google

```
┌────────────────────────────────────────────────────┐
│                                                    │
│        The member directory is for members         │
│                                                    │
│   Sign in to search 142 member companies.          │
│                                                    │
│        [ Log in ]      [ Become a member ]         │
│                                                    │
└────────────────────────────────────────────────────┘
```

No company names, no cities, no count of who is listed — the "142" is the total member count, already public on the About page, not a directory read. Nothing is indexed.

### 4.2 Vikram — signed up last week, `PENDING`, unpaid

```
┌────────────────────────────────────────────────────┐
│                                                    │
│     🔒 The directory unlocks when you join         │
│                                                    │
│   Your membership is pending payment.              │
│   Invoice INV/2026-27/00318 · ₹25,000              │
│                                                    │
│   Once paid, you can search all 142 members        │
│   and contact them directly.                       │
│                                                    │
│                  [ Pay now ]                       │
│                                                    │
└────────────────────────────────────────────────────┘
```

**Zero companies.** Logging in bought him nothing; paying will. When the invoice is marked paid his status flips to `ACTIVE` and he is in on his next request — no admin grants him anything.

### 4.3 Meena — owns Sunrise Foods, `ACTIVE`

```
┌────────────────────────────────────────────────────┐
│  Member Directory                    142 members   │
├────────────────────────────────────────────────────┤
│  🔍 spices          City: Ahmedabad ▾   Category ▾ │
├────────────────────────────────────────────────────┤
│  ┌──────┐  Shreeji Exports Pvt Ltd                 │
│  │ logo │  Ahmedabad, Gujarat                      │
│  └──────┘  Spices · Agri Commodities               │
├────────────────────────────────────────────────────┤
│  ┌──────┐  Gujarat Spice Traders                   │
│  │ logo │  Rajkot, Gujarat                         │
│  └──────┘  Spices                                  │
└────────────────────────────────────────────────────┘
```

Kiran Traders is absent — `EXPIRED`, so not listed, even though Meena is fully entitled to look.

Opening Shreeji:

```
┌────────────────────────────────────────────────────┐
│  ┌──────┐  Shreeji Exports Pvt Ltd                 │
│  │ logo │  LGDGF/2026/0042 · Member since 2026     │
│  └──────┘  Ahmedabad, Gujarat                      │
├────────────────────────────────────────────────────┤
│  About     Spice and agri-commodity exporters      │
│            since 1998.                             │
│  Business  Spices · Agri Commodities               │
│  Website   shreejiexports.in                       │
├────────────────────────────────────────────────────┤
│  ── Contact ───────────────────────────────────    │
│  Rakesh Patel, Director                            │
│  📞 +91 98250 12345                                │
│  ✉  rakesh@shreejiexports.in                       │
└────────────────────────────────────────────────────┘
```

She still does **not** see GST, PAN, IEC or KYC documents. No member sees another member's tax identifiers.

### 4.4 Rakesh opts out

He unticks "list my company". Meena's search now returns one result instead of two. Rakesh himself is unaffected as a viewer — still `ACTIVE`, still searching, simply not listed.

### 4.5 Priya — association staff

Priya does not use the directory. She uses the existing Members screen, which already shows everything, with phone and email masked behind the `sensitive_data` permission per the `phi-masking` convention. The directory adds one column there and nothing else.

### 4.6 One year later

31 March passes. Kiran Traders does not renew. `status` becomes `EXPIRED`. That night, with no admin action, **two doors close at once**:

- Kiran disappears from every member's search results (switch 2)
- Kiran loses access — logging in, he now sees the `EXPIRED` lock screen (§2.2)

One status change; both consequences. That symmetry is the design.

---

## 5. Field allowlist — frozen

One list, because only `ACTIVE` members ever receive a response. This is an explicit column allowlist, never "everything minus" — a column added to `Members` next year is invisible until somebody deliberately adds it here.

| Field | Source | Returned |
|---|---|---|
| `companyName` | `Members.company_name` | yes |
| `slug` | derived from company name + id | yes |
| `city`, `state` | primary `MemberAddress` | yes |
| `categories[]` | `MemberCategory` → `MembershipCategory.name` | yes |
| `website` | `Members.website` | yes |
| `about` | `Members.about` | yes |
| `logoUrl` | opaque id over `Members.logo_path` | yes |
| `memberCode` | `Members.member_code` | yes |
| `joinedYear` | `Members.joined_on`, year only | yes |
| `contact.name`, `contact.designation` | primary `MemberContact` | yes |
| `contact.phone`, `contact.email` | primary `MemberContact` | yes |
| `contacts[]` | **every** `MemberContact`, primary first | yes — profile only (D-6) |
| `companyType` | `CompanyTypes.name` | yes — profile only (D-6) |
| `address` (street lines, pincode, country) | primary `MemberAddress` | yes — profile only (D-6) |
| `legalName` | `Members.legal_name` | **no — searched, never returned** |
| `gstNumber`, `panNumber`, `iecCode`, `tradeLicenseNo` | `Members` | **no** |
| Any `MemberDocument` | KYC evidence | **no** |

### Amendment D-6 — the profile publishes the address, the type and every contact

**Decided 2026-09-01, by the client, overriding the rows above.** The table has
been updated; this note records what changed and why, because the reasoning in
the original three choices no longer describes all of it.

| Field | Was | Now |
|---|---|---|
| Street lines, pincode, country | never returned | on the **profile** |
| Company type | not published | on the **profile** |
| Contacts | the primary only | **all** of them, primary marked and first |

Three things did **not** change, and the tests still pin them:

- **Nothing moved onto the card.** The card is the search result; the profile is
  a page someone opened on purpose. A listing carrying every member's door and
  every manager's mobile is the scrape this module exists to prevent.
- **The gate is untouched.** All of it is still behind an ACTIVE membership, and
  still absent from every anonymous response.
- **GST, PAN, IEC, trade licence, the registered legal name and KYC documents
  remain unpublished.** Those sit between a member and the association.

The disclosure this widens is real and worth stating plainly: a member can now
read another member's street address and the direct line of every contact that
company has published — not just its switchboard. That is the association's call
to make, and it made it.

Three deliberate choices:

- **`legalName` is searched but never returned.** A member who knows the registered name should find the company; returning both names invites impersonation and adds nothing to the card.
- **Joining date is returned as a year.** "Member since 2026" is the useful signal; the exact date is not.
- **`logo_path` is never returned.** The client receives an opaque media id resolved through a serving endpoint, exactly as the news module already does for its images.

---

## 6. Backend

One new module, `backend/src/modules/directory`, following the shape of `modules/news`:

```
directory.constants.ts   field allowlist, page size, sort options
directory.types.ts       query and response types
directory.repository.ts  Prisma queries, search, pagination
directory.presenter.ts   shapes the response from the allowlist
directory.service.ts     resolves the viewer gate, applies the three switches
directory.controller.ts  thin
directory.routes.ts      one router
```

### 6.1 Routes

`END_POINTS.DIRECTORY` (`/directory`) is already reserved in `constant/endPoints.constant.ts`. **One router, member-authenticated. No `/public/directory` router exists.**

| Method | Path | Auth | Returns |
|---|---|---|---|
| GET | `/api/v1/directory` | member token + `ACTIVE` | listing, paginated |
| GET | `/api/v1/directory/:slug` | member token + `ACTIVE` | one company |
| GET | `/api/v1/directory/media/:publicId` | member token + `ACTIVE` | logo bytes |
| GET | `/api/v1/directory/filters` | member token + `ACTIVE` | category and city facets |

The logo endpoint is gated like the rest. A public media route would leak the fact that a given company is a member, and would let logo URLs be shared outside the wall.

### 6.2 The viewer gate

Resolved once, in the service, before any query runs:

```
token missing            → 401
load caller's Member (status only) from the database
status != ACTIVE         → 403 { reason: NO_MEMBERSHIP | PAYMENT_PENDING
                                       | EXPIRED | SUSPENDED }
otherwise                → proceed
```

The status is read from the database on **every** request, never trusted from a claim inside the token. A member suspended five minutes ago must lose access on their next request, not when their token expires.

The `403` carries a reason code and nothing else. It never carries a partial listing, a company count, or any company name.

### 6.3 The listing query

The base `WHERE` is fixed and non-negotiable:

```
deletedAt IS NULL
AND status = 'ACTIVE'
AND directory_visible = true
```

preceded by a check that `SystemSettings['directory.enabled']` is true; when it is false the endpoint returns an empty result with an explanatory code rather than an error.

- **Search:** full-text over `company_name`, `legal_name` and `about` via a Postgres GIN index — the only schema change the module needs. Both the trading name and the registered legal name are searchable; only the trading name is displayed.
- **Filters:** category (multi), city, state.
- **Sort:** relevance when a search term is present, otherwise company name ascending.
- **Pagination:** 24 per page, hard server cap. `?limit=10000` returns 24.

### 6.4 Slugs

Derived, not stored: `slugify(company_name) + '-' + id`, e.g. `shreeji-exports-pvt-ltd-42`. Two companies may share a trading name; the id suffix keeps the URL unique without a new column or a uniqueness constraint on a field members can edit. A lookup parses the trailing id and verifies the slug, redirecting if the company has since renamed, so links shared between members do not rot.

---

## 7. Customer frontend

Everything lives under `customer/src/app/(member)/directory/`. The existing placeholder at `(public)/directory/page.tsx` is **removed**, not repurposed — the route must not exist on the public side of the site.

**List page** — search box, category and city filters, result cards, pagination. Behind the member layout, so the existing auth guard applies before any directory code runs.

**Profile page** — one company, as in §4.3.

**Lock screen** — rendered when the API returns `403`, with copy chosen by the reason code (§2.2). This is a real screen with a real call to action, not an error state.

**Member control** — on the existing profile settings page: the "list my company in the directory" tick-box and the `about` text area, with a line stating the current effective state:

- *"Listed — members can find your company"*
- *"Hidden — you have opted out"*
- *"Hidden — your membership is not active"*

Each screen states the four-part contract required by `docs/ux-principles.md`:

| | List page | Lock screen | Member settings |
|---|---|---|---|
| **Current state** | You are searching 142 member companies | Your membership is pending payment | Your company is listed |
| **Required action** | Search by name, category or city | Pay invoice INV/2026-27/00318 | Tick or untick, then save |
| **Next step** | Open a company profile | The directory unlocks | Change takes effect immediately |
| **Expected result** | You find and can contact the member | You can search and contact all members | You appear, or stop appearing, to other members |

---

## 8. Admin

Deliberately minimal — no new screen.

- **Members table:** one new read-only column, *In directory*, showing `Listed` / `Hidden — member's choice` / `Hidden — not active` / `Hidden — directory off`. It explains; it does not control.
- **Member detail:** an admin override to force-hide a specific company, written to `Members.directory_visible` with an audit entry. The association can hide a member; it cannot force-show one who opted out.
- **System settings:** one boolean, `directory.enabled`.

All admin work uses the `association-admin-ui` component catalogue — no direct Ant Design imports.

---

## 9. Migration

One migration, additive only:

- GIN full-text index over `company_name`, `legal_name`, `about` on `Members`.
- A supporting index for the city/state filter path on `MemberAddresses`.

No column is added, changed or dropped. `directory_visible`, `about`, `website` and `logo_path` all already exist on `Members`, and `@@index([directory_visible, status])` is already applied.

---

## 10. Tests

The `directory` suite. The first three are the ones that matter:

1. **Anonymous** — request the listing with no token → `401`, and the body contains no company name.
2. **Non-active** — request with a `PENDING` member's token → `403` with reason `PAYMENT_PENDING`, and the raw response bytes contain no company name, no `98250`, and no company count.
3. **Active** — an `ACTIVE` token gets the listing and the contact block, and still no GST, PAN or IEC anywhere in the payload.
4. **Status is live** — suspend a member mid-session; their next request returns `403` on the existing token.
5. Each listing switch alone: `EXPIRED` company disappears · `directory_visible = false` disappears · `directory.enabled = false` empties the listing.
6. **Opt-out asymmetry** — a member with `directory_visible = false` can still search successfully.
7. Search matches on `company_name`, on `legal_name`, and on `about`; a SQL-injection string returns an ordinary empty result.
8. Pagination cap holds against `?limit=10000`.
9. The logo endpoint returns `401` without a token and `403` for a non-active member.
10. No directory route appears in the public sitemap, and `(public)/directory` returns the app's 404.

Definition of done: the allowlist is enforced server-side and asserted key-by-key; no company data of any kind can reach a non-`ACTIVE` caller; the viewer's status is re-read per request.

---

## 11. Out of scope

Not built here, and not to be added without a separate decision:

- **Per-profile view permissions.** GJEPC requires a member to request permission before viewing another member's profile. That is a heavier consent model than this association has asked for; every `ACTIVE` member can see every listed member.
- Member-to-member messaging inside the platform. The directory hands over a phone number and an email; the conversation happens outside.
- Enquiry or lead-capture forms on a profile.
- Featured, sponsored or ranked placement.
- Member self-uploaded photo galleries or product catalogues.
- Export of the directory to Excel by members — this would defeat the gating in one click. Admin export already exists on the Members screen.
- Any public or SEO surface. Should the association later want a public face, that is a separate module over the same data, not a relaxation of this one.

---

## 12. Open questions

| # | Question | Working assumption |
|---|---|---|
| DIR-1 | Should a company with no `about` text and no logo still be listed, or held back until its profile is minimally complete? | **Listed.** Hiding them would silently penalise members who have paid. |
| DIR-2 | Should the association be notified when a member opts out? | **No alert.** The *In directory* column on the Members screen already shows it, so staff can see it whenever they look without being pinged per tick-box. |

Two earlier open questions are dissolved by the members-only decision and need no answer: whether logos may be shown publicly, and whether non-members may search. Nothing is public, and there are no non-member viewers.

Neither remaining question blocks implementation; each has a stated working assumption.
