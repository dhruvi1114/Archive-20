# News Module — Simple Summary

**Status:** planned, not built. Belongs to M9 (public website).
Full design detail will live in the spec file; this page is the easy version.

---

## What it is

A News section the association writes itself in the admin panel. It shows on the
public website — the homepage Newsroom block, a `/news` page, and one page per article.

**News is not the same as circulars.**

| | News | Notices / Circulars (M8) |
|---|---|---|
| Who it is for | The whole world | Chosen members only |
| Login needed | No (unless marked members-only) | Yes |
| Shows on Google | Yes | No |
| Sends email / bell alert | No | Yes |

---

## The flow in 6 steps

1. **Write** — Admin opens News → Add. Fills title, category, excerpt, cover photo,
   rich text body, optional PDF. Clicks **Save Draft**. Website unchanged.
2. **Publish** — Admin clicks **Publish**. Status becomes PUBLISHED and the date is stamped.
3. **Website updates itself** — the article appears at the top of `/news`, becomes card 1
   in the homepage Newsroom block (oldest card drops off), and is added to the sitemap.
4. **People read it** — visitors land from Google or the homepage, read the article,
   download the PDF.
5. **Visibility rule applies** — see the table below.
6. **Archive** — old news can be archived. It disappears from the website but stays
   in the admin panel and the database. Nothing is deleted.

---

## Who can see what

Each article has one setting: **Public** or **Members only**.

| Article is | Non-member (no login) | Logged-in member |
|---|---|---|
| Public | sees it | sees it |
| Members only | not in the list, URL gives 404, PDF gives 403 | sees it, with a "Members only" chip |

A member always sees more than a visitor — all public news **plus** members-only news.
Default when writing a new article is **Public**.

---

## Categories

Labels that group news so visitors can filter, e.g. Press Release, Industry News,
Event Coverage, Association Update.

- Admin picks one from a dropdown when writing.
- The `/news` page shows them as filter tabs.
- The category list itself is editable in a small admin screen — the association
  chooses its own names.

---

## What gets built

**Database — 3 tables**

| Table | Holds |
|---|---|
| `NewsCategory` | the filter labels |
| `NewsArticle` | one row per article: slug, title, excerpt, body, cover image, category, public/members-only, status, published date, optional PDF |
| `NewsArticleImage` | photos placed inside the article body |

**Admin screens — 3**

- News list (search, filter, publish / unpublish / archive)
- News editor (rich text, cover image, PDF, visibility toggle)
- News categories (small CRUD list)

**Website screens — 2 + 1 block**

- Homepage Newsroom block — latest 4 published, automatic
- `/news` — category tabs, newest-first cards, Load More
- `/news/[slug]` — the article page, server-rendered with share/SEO tags

**Permissions:** `news.view`, `news.manage` — same pattern as `event.*`.

---

## Safety rules

- Article HTML is cleaned on the server before saving, so a pasted `<script>`
  cannot run on the public homepage.
- Uploads are checked by real file content, not by the name. No SVG.
- Cover and inline photos are web-served; PDFs are not — they are downloaded
  through the API, which checks visibility first.
- Drafts, archived and members-only articles are filtered out in the database
  query, never by the frontend.

---

## New tool needed

**TipTap** rich text editor for the admin app. Version must be pinned in
`versions.md` so both coding agents use the same one. Nothing else in the
stack changes.

---

## Still to decide

1. Keep categories? (recommended: yes)
2. One PDF per article, or several? (planned: one)
3. Should publishing a members-only article send a bell/email alert? (planned: no)
