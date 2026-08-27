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

## Schema (actual columns)

Follows the conventions already used by `event.prisma`: `BigInt` surrogate keys,
enum columns stored as `smallint` codes (the rule for every table created from M7
onward), `Timestamptz(6)` timestamps, soft delete via `deletedAt`.
Lives in a new file `backend/prisma/schema/content.prisma`.

### NewsCategory → table `NewsCategories`

| Column | Type | Notes |
|---|---|---|
| `id` | BigInt PK | surrogate key |
| `code` | varchar(30) UNIQUE | stable machine name, e.g. `PRESS_RELEASE`. Immutable |
| `name` | varchar(120) | shown in the dropdown and the filter tab, e.g. "Press Release" |
| `slug` | varchar(140) UNIQUE | used in the URL `/news?category=press-release` |
| `display_order` | int default 0 | tab order, lower first |
| `is_active` | bool default true | deactivated, never deleted, once used |
| `createdAt` / `updatedAt` / `deletedAt` | timestamptz | `deletedAt` NULL = live |
| `created_by_admin_id` / `updated_by_admin_id` | BigInt? | staff audit |

Index: `(is_active, display_order)`

### NewsArticle → table `NewsArticles`

| Column | Type | Notes |
|---|---|---|
| `id` | BigInt PK | |
| `slug` | varchar(180) UNIQUE | the URL, e.g. `gjepc-seminar-b2b-e-commerce-delhi`. Generated from the title, editable while DRAFT, frozen once published so links never break |
| `title` | varchar(220) | |
| `excerpt` | varchar(400) | the two lines on the card. Required — the card looks broken without it |
| `body` | text | rich text HTML, sanitised on the server before it is stored |
| `cover_image_path` | varchar(300) | `public/news/47/cover-a7f3.jpg` |
| `cover_image_alt` | varchar(200) | accessibility + SEO |
| `category_id` | BigInt? FK → NewsCategories | ON DELETE RESTRICT. Nullable so a category can be retired without orphaning |
| `visibility` | smallint default 1 | **0 = MEMBER_ONLY, 1 = PUBLIC.** Same codes as `Event.visibility`. Member-only rows are absent from public queries, never fetched and hidden |
| `status` | smallint default 0 | **0 = DRAFT, 1 = PUBLISHED, 2 = ARCHIVED** |
| `published_at` | timestamptz? | stamped once, on the first publish. Sort key for every listing |
| `attachment_path` | varchar(300)? | the PDF, stored OUTSIDE the web root |
| `attachment_name` | varchar(200)? | original filename, shown on the download button |
| `attachment_size` | int? | bytes, shown beside the button |
| `createdAt` / `updatedAt` / `deletedAt` | timestamptz | |
| `created_by_admin_id` / `updated_by_admin_id` | BigInt? | |

Indexes:
- `(status, visibility, published_at DESC)` — the homepage block and `/news` listing
- `(category_id, status, published_at DESC)` — the category filter
- `slug` unique — the article page lookup

CHECK: `status = 1` requires `published_at IS NOT NULL`.

### NewsArticleImage → table `NewsArticleImages`

Photos placed inside the body. Kept as rows so the files can be cleaned up when
the article is deleted, and so an orphan sweep can find uploads that were never used.

| Column | Type | Notes |
|---|---|---|
| `id` | BigInt PK | |
| `article_id` | BigInt FK → NewsArticles | ON DELETE CASCADE |
| `path` | varchar(300) | `public/news/47/inline-b210.jpg` |
| `original_name` | varchar(200) | |
| `size_bytes` | int | |
| `createdAt` | timestamptz | |

Index: `(article_id)`

### Prisma sketch

```prisma
model NewsArticle {
  id                  BigInt    @id @default(autoincrement())
  slug                String    @unique @db.VarChar(180)
  title               String    @db.VarChar(220)
  excerpt             String    @db.VarChar(400)
  body                String    @db.Text
  cover_image_path    String    @db.VarChar(300)
  cover_image_alt     String?   @db.VarChar(200)
  category_id         BigInt?
  /// 0 = MEMBER_ONLY, 1 = PUBLIC
  visibility          Int       @default(1) @db.SmallInt
  /// 0 = DRAFT, 1 = PUBLISHED, 2 = ARCHIVED
  status              Int       @default(0) @db.SmallInt
  published_at        DateTime? @db.Timestamptz(6)
  attachment_path     String?   @db.VarChar(300)
  attachment_name     String?   @db.VarChar(200)
  attachment_size     Int?
  createdAt           DateTime  @default(now()) @db.Timestamptz(6)
  created_by_admin_id BigInt?
  updatedAt           DateTime  @updatedAt @db.Timestamptz(6)
  updated_by_admin_id BigInt?
  deletedAt           DateTime? @db.Timestamptz(6)

  category NewsCategory?      @relation(fields: [category_id], references: [id])
  images   NewsArticleImage[]

  @@index([status, visibility, published_at])
  @@index([category_id, status, published_at])
  @@map("NewsArticles")
}
```

### What the codes mean in practice

| `status` | `visibility` | Non-member sees | Member sees |
|---|---|---|---|
| 0 DRAFT | any | nothing | nothing |
| 1 PUBLISHED | 1 PUBLIC | yes | yes |
| 1 PUBLISHED | 0 MEMBER_ONLY | nothing, URL 404 | yes, with chip |
| 2 ARCHIVED | any | nothing | nothing (admin only) |

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
