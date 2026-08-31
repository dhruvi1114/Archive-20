# Member Directory — Simple Summary

**Status:** planned, not built. Belongs to M9 (public website), the other half from News.
Full design detail is in `docs/specs/2026-08-31-member-directory.md`; this page is the easy version.

**The one-line version:** a phone book of member companies that only paid, active members can open.

---

## What it is

A searchable list of the association's member companies, living **behind the login**
in the member portal. Members search by name, city or business category, open a
company, and get the contact person's phone and email.

**It is not a public page.** Despite belonging to M9, nothing here appears on the
public website or on Google.

| | Directory (M9) | News (M9) | Members screen (M3) |
|---|---|---|---|
| Who it is for | Paid members only | The whole world | Association staff |
| Login needed | Yes, and must be ACTIVE | No | Yes, admin |
| Shows on Google | **No** | Yes | No |
| Shows GST / PAN / KYC | Never | — | Yes |
| Who is listed | Only paid, active, opted-in members | — | Every company, every status |

---

## The flow in 6 steps

1. **Nothing to write** — unlike News, nobody creates a directory entry. It is
   built automatically from the member records the platform already holds.
2. **A member pays** — their `status` flips to `ACTIVE`. Two things happen at
   once: they can now **open** the directory, and they now **appear** in it.
3. **The member tunes their listing** — on their profile page they write a short
   description, and can untick "list my company" to hide themselves.
4. **Members search each other** — a member looking for a spice supplier searches
   "spices", filters by city, opens the company, and calls them.
5. **Everyone else is locked out** — see the table below. A stranger sees a
   sign-in prompt. An unpaid signup sees a "pay now" screen. Neither sees a
   single company name.
6. **A member lapses** — they do not renew, `status` becomes `EXPIRED`, and they
   both drop out of the listing **and** lose access. Nothing is deleted.

---

## Who can see what

There is no per-company public/private setting like News has. The rule is the
**viewer's own membership status**.

| Viewer | Their company status | Can they open the directory? |
|---|---|---|
| Stranger from Google | none | **No** — sign-in prompt |
| Signed up, not approved | DRAFT / PENDING | **No** — "pay now" screen |
| Approved, invoice unpaid | PENDING | **No** — "pay now" screen |
| Paid member | **ACTIVE** | **Yes** |
| Lapsed member | EXPIRED / SUSPENDED | **No** — "renew" screen |
| Association staff | admin | Via the Members screen, not the directory |

**Having a login is not the gate — being ACTIVE is.** If merely logging in were
enough, anyone could fill the two-minute signup form and take all 142 phone
numbers without paying, and every lapsed member would keep the benefit forever.

A locked-out viewer gets **no company data at all** — not names, not cities, not
even a count. Only a message telling them what to do:

| Viewer | Screen they see |
|---|---|
| Stranger | "The member directory is for members." `[Log in]` `[Become a member]` |
| Unpaid | "Your membership is pending payment. Invoice INV/2026-27/00318 · ₹25,000" `[Pay now]` |
| Expired | "Your membership expired on 31 Mar 2026." `[Renew]` |
| Suspended | "Your membership is currently suspended. Please contact the association." |

That "pay now" screen is the business case for the whole module. It tells a
prospective member exactly what their fee buys, with the payment button right there.

**No member ever sees another member's GST, PAN, IEC or KYC documents.** Those
stay between the member and the association.

---

## Two different questions

These are easy to mix up. They are separate.

| | **Can I look?** | **Am I listed?** |
|---|---|---|
| Decided by | My own company's status | My status **+** my tick-box **+** the global switch |

So a member who opts out of being listed **can still search the directory**.
Opting out hides you; it does not resign you from the benefit.

---

## The three switches — who gets listed

A company appears in the listing only when all three are true.

| Switch | Where it lives | Who controls it | Example |
|---|---|---|---|
| Directory is on | `SystemSettings` key `directory.enabled` | Association | Turned off during a data cleanup |
| Membership is current | `Members.status = ACTIVE` | The system, automatically | Kiran Traders does not renew → gone that night |
| Member consents | `Members.directory_visible` | The member | Rakesh unticks the box → gone, still a paid member |

Switch 2 is what makes the directory trustworthy over years: a company that
stopped paying can never quietly stay listed, because no human step is involved.

---

## Categories

The directory reuses the **existing** membership categories from M2 — Grower,
Manufacturer, Trader and so on. No new category table.

- A company already claims one or more at registration (`MemberCategories`).
- The directory page shows them as filter chips.
- The list comes from `MembershipCategories`, edited on the existing masters screen.

---

## What gets built

**Database — 0 new tables**

This is the big difference from News. Every field the directory needs already
exists on `Members`, `MemberContacts`, `MemberAddresses` and `MemberCategories`.
Only one migration is needed, and it adds indexes, not columns.

**Backend — 1 new module, 1 router**

`backend/src/modules/directory`, same seven-file shape as `modules/news`. News
needed two routers, public and member. The directory needs **one**, because
there is no public audience.

**Admin screens — 0 new**

- Members list: one new read-only column, *In directory*
- Member detail: an admin force-hide toggle
- System settings: one on/off switch

**Member portal screens — 2 + 1 lock + 1 control**

- `/directory` — search box, category and city filters, cards, pagination
- `/directory/[slug]` — the company profile
- The lock screen, shown to anyone not ACTIVE
- Member profile settings: the "list my company" tick-box and description box

The existing placeholder at `(public)/directory` is **deleted**. The route must
not exist on the public side of the site.

**Permissions:** no new ones. The member token plus an ACTIVE status check is the
whole gate; the admin column uses `member.view`.

---

## Schema (what it reads)

No new tables. This is the exact field map.

### From `Members`

| Column | Already exists | Used for |
|---|---|---|
| `company_name` varchar(200) | yes | the card title — **searched and shown** |
| `legal_name` varchar(200)? | yes | **searched, never shown** |
| `about` text? | yes | the description — searched and shown |
| `website` varchar(200)? | yes | the profile link |
| `logo_path` text? | yes | the logo, served through an opaque id — the path never leaves the server |
| `member_code` varchar(30)? | yes | shown on the profile |
| `joined_on` date? | yes | shown as a **year** only: "Member since 2026" |
| `status` enum | yes | used **twice** — the viewer's gate, and switch 2 for listing |
| `directory_visible` bool | yes | switch 3 |
| `gst_number`, `pan_number`, `iec_code`, `trade_license_no` | yes | **never read by this module** |

`@@index([directory_visible, status])` is already on the model.

### From `MemberContacts` (the `is_primary` row)

`name`, `designation`, `phone`, `email` — all shown to ACTIVE members.

### From `MemberAddresses` (the `is_primary` row)

| Column | Shown |
|---|---|
| `city`, `state` | yes |
| `pincode`, street lines | **no** |

### From `MemberCategories` → `MembershipCategories`

`name` varchar(120) only — shown as chips and used as a filter.

### The one migration

```sql
-- full-text search: BOTH the trading name and the legal name, plus the description
CREATE INDEX members_directory_fts_idx ON "Members"
  USING GIN (to_tsvector('english',
    coalesce(company_name,'') || ' ' ||
    coalesce(legal_name,'')  || ' ' ||
    coalesce(about,'')));

-- supports the city / state filter join
CREATE INDEX member_addresses_city_idx ON "MemberAddresses" (city, state)
  WHERE is_primary = true;
```

Additive only. No column is added, changed or dropped.

### The URL slug

Derived, not stored: `slugify(company_name) + '-' + id`, e.g.
`shreeji-exports-pvt-ltd-42`. Two companies may share a trading name, so the id
keeps it unique without a new column. A lookup reads the trailing id and
redirects if the company has since renamed — links shared between members don't rot.

---

## Worked example

**Shreeji Exports Pvt Ltd**, Ahmedabad, spices, ACTIVE, listed.

**A stranger** types the directory URL:

```
The member directory is for members
Sign in to search 142 member companies.
[ Log in ]   [ Become a member ]
```

**Vikram**, signed up last week, invoice unpaid:

```
🔒 The directory unlocks when you join
Your membership is pending payment.
Invoice INV/2026-27/00318 · ₹25,000
[ Pay now ]
```

Zero companies. Logging in bought him nothing — paying will.

**Meena**, a paid ACTIVE member, searches "spices" and opens Shreeji:

```
Shreeji Exports Pvt Ltd
LGDGF/2026/0042 · Member since 2026
Ahmedabad, Gujarat
Spices · Agri Commodities
shreejiexports.in
"Spice and agri-commodity exporters since 1998."

Rakesh Patel, Director
📞 +91 98250 12345
✉  rakesh@shreejiexports.in
```

She calls Rakesh. **That is the product.**

**What nobody outside the admin app ever sees:**

```
GST 24AABCS1234F1Z5 · PAN AABCS1234F · IEC 0398012345 · KYC files
```

**Next March**, Kiran Traders does not renew. `status` → `EXPIRED`. That night,
two doors close at once: Kiran vanishes from everyone's search results, **and**
Kiran logging in now sees the "renew" screen. One status change, both effects,
nobody clicked anything.

---

## Safety rules

- The gate runs **before any query**. A non-active caller gets a `403` with a
  reason code and nothing else — no partial list, no company count, no names.
- The viewer's membership status is read from the **database on every request**,
  not trusted from the token. A member suspended five minutes ago loses access on
  their next click, not when their token expires.
- The field list is an explicit allowlist — "these columns", never "everything
  minus these". A new column added to `Members` next year is invisible by default.
- Non-active, hidden and non-listed companies are filtered in the **database
  query**, never by the frontend.
- The logo endpoint is gated too. A public logo URL would leak the fact that a
  company is a member, and could be shared outside the wall.
- Pagination is capped server-side at 24 rows. `?limit=10000` returns 24.
- The directory appears in no sitemap, and `(public)/directory` returns a 404.

---

## New tool needed

**None.** No new library, no new table, no new permission. The GIN index uses
Postgres' built-in full-text search. This is the cheapest remaining module — and
members-only made it cheaper still: one router instead of two, one field list
instead of two, and no SEO or server-rendering work at all.

---

## Tests that matter

1. **No token** → `401`, and no company name anywhere in the response.
2. **PENDING member's token** → `403` reason `PAYMENT_PENDING`, and the raw bytes
   contain no company name, no `98250`, and no company count.
3. **ACTIVE token** → gets the listing and contacts, and still no GST, PAN or IEC.
4. Suspend a member mid-session → their **next** request on the same token fails.
5. A member who opted out of being listed can **still search successfully**.
6. Search finds a company by its trading name, by its legal name, and by its
   description.
7. A SQL-injection string in the search box returns an ordinary empty result.

---

## Still to decide

1. Should a company with **no description and no logo** still be listed, or held
   back until the profile is filled in? (planned: listed — hiding them would
   silently penalise members who paid)
2. Should the association be **notified** when a member opts out? (planned: no
   alert — the *In directory* column on the Members screen already shows it,
   so staff can see it whenever they look)

Two earlier questions no longer apply, now that the directory is members-only:
whether logos may be public, and whether strangers may search. Nothing is public,
and there are no strangers.
