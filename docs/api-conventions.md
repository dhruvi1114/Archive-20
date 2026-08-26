# API Conventions

## 1. Base

- Base path `/api/v1`. Version bumps only on breaking change.
- Member endpoints: `/api/v1/<resource>`; admin endpoints: `/api/v1/admin/<resource>`; public (no auth): `/api/v1/public/<resource>`.
- JSON only (`application/json`), except uploads (`multipart/form-data`).
- All timestamps ISO-8601 UTC. Money as a string with 2 decimals (`"12500.00"`) to avoid float drift on the wire.

## 2. Encrypted transport (ADR-004)

**Request** (POST/PUT/PATCH):
```json
{ "data": "U2FsdGVkX1+9k…" }     // AES-256-CBC( gzip( JSON.stringify(payload) ) )
```
`decryptPayload` middleware replaces `req.body` with the parsed object before validation. GET/DELETE query params are **not** encrypted (they must stay cacheable and loggable) — never put a secret in a query string.

**Response**:
```json
{
  "success": true,
  "statusCode": 200,
  "message": "Data fetched successfully",
  "data": "U2FsdGVkX1+…",
  "pagination": { "page": 1, "limit": 20, "total": 153, "totalPages": 8 }
}
```
`APP_ENV=local` adds `"decrypted_data": { … }`. Never in dev/staging/production.

**Bypass list** (plaintext body, still authenticated/validated): `POST /api/v1/**/upload*` (multipart), `POST /api/v1/webhooks/**` (provider-signed), `GET /api/v1/health`.

Encryption is obfuscation, not authorization. Every route still runs authn → authz → zod validation after decryption.

## 3. Headers

| Header | Purpose |
|---|---|
| `Authorization: Bearer <jwt>` | access token |
| `lan: en` | i18n locale (defaults to `APP_LANGUAGES[0]`) |
| `x-request-id` | client-supplied correlation id; echoed in logs and error responses |

## 4. Success shapes

| Case | statusCode | `data` |
|---|---|---|
| Create | 201 | created object |
| Read one | 200 | object |
| Read list | 200 | array + `pagination` |
| Update | 200 | updated object |
| Delete (soft) | 200 | `{ id }` |
| Action (approve/pay/…) | 200 | resulting object + `nextStep` hint where the UX needs it |

`message` always comes from i18n, never a literal.

## 5. Error shape

```json
{
  "success": false,
  "statusCode": 422,
  "message": "Please provide required fields",
  "code": "VALIDATION_ERROR",
  "error": { "fields": { "gst_number": "Invalid GST format" } }
}
```

| `code` | HTTP | Thrown when |
|---|---|---|
| `VALIDATION_ERROR` | 422 | zod failure |
| `INVALID_REQUEST` | 400 | malformed/undecryptable payload |
| `UNAUTHORIZED` | 401 | missing/expired/invalid token |
| `FORBIDDEN` | 403 | authenticated but lacks permission or wrong audience |
| `NOT_FOUND` | 404 | resource absent or not visible to this actor |
| `CONFLICT` | 409 | uniqueness / duplicate / concurrent-state clash |
| `INVALID_STATE_TRANSITION` | 409 | workflow guard rejected the move |
| `PAYMENT_FAILED` | 402 | gateway declined |
| `RATE_LIMITED` | 429 | throttle |
| `INTERNAL_ERROR` | 500 | anything unexpected — stack logged, never returned |

Never leak Prisma errors, SQL, stack traces or table names to clients.

## 6. Pagination, filtering, sorting

`?page=1&limit=20&sortBy=createdAt&sortOrder=desc&search=…&status=…`
- `limit` default 20, **max 100** (server clamps, never errors).
- `search` is a single free-text field per resource; documented per endpoint which columns it hits.
- Filters are explicit named params — no generic `filter[...]` passthrough to SQL.
- Sorting only on a per-endpoint allowlist of columns; anything else → 422.
- Every list query is a single SQL statement with joins (no N+1) and returns `total` from a windowed count.

## 7. Idempotency & concurrency

- Payment initiation and webhook handling are idempotent (unique `provider_order_id` / `(provider,event_id)`).
- State-changing actions (approve, reject, pay, register) accept the entity's current `status`/`updatedAt` where a race is realistic and return `409 INVALID_STATE_TRANSITION` on mismatch.

## 8. Uploads

`multipart/form-data`, single field `file` (+ `document_type_code`). Server validates MIME against `DocumentTypes.allowed_mime`, size against `max_size_mb`, computes SHA-256, stores outside the public static root, returns metadata only. Downloads go through `GET /api/v1/documents/:id/download` with authorization; **no direct static URL for KYC files**.

## 9. Rate limits

| Scope | Limit |
|---|---|
| Global per IP | 300 req / 15 min |
| `POST /auth/login`, `/auth/admin/login` | 5 / 15 min per IP+identifier |
| `POST /auth/otp/*`, `/auth/forgot-password` | 3 / 15 min per identifier |
| Public directory/search | 60 / min per IP |

## 10. Naming

Resources plural and kebab-free (`/membership-applications` is allowed where the domain word is compound). Actions as sub-resources: `POST /admin/membership-applications/:id/approve`. No verbs in collection paths, no RPC-style `/doApprove`.
