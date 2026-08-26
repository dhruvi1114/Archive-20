# File Storage Rules

Covers KYC documents, application documents, invoice/receipt PDFs, notice attachments, event banners and member logos. KYC files are the most sensitive data in the system; the rules below are written for them and applied to everything.

## 1. Driver abstraction (A-7, ADR-017)

```ts
interface StorageAdapter {
  put(key: string, body: Buffer | Readable, meta: {mime: string; size: number}): Promise<{key: string; checksum: string}>;
  getStream(key: string): Promise<Readable>;
  delete(key: string): Promise<void>;
  exists(key: string): Promise<boolean>;
}
```
`STORAGE_DRIVER=local|s3`. MVP ships `local`. Callers never touch `fs` or the AWS SDK directly, so the S3 move is one file plus env — no change in any service.

## 2. Key layout (never a client-supplied path)

```
<STORAGE_PATH>/
  members/<member_id>/kyc/<document_type_code>/<uuid>.<ext>
  applications/<application_id>/<document_type_code>/<uuid>.<ext>
  invoices/<invoice_id>/<invoice_number>.pdf
  receipts/<payment_id>/<receipt_number>.pdf
  notices/<notice_id>/<uuid>.<ext>
  events/<event_id>/banner-<uuid>.<ext>
  public/                      # ONLY this subtree may ever be web-served
```

Rules: filename is a server-generated UUID — the original name is stored in the DB column, never on disk. The original name is never used to build a path (defeats traversal, unicode and case-collision attacks). `path.resolve` the final key and assert it is still inside `STORAGE_PATH` before any write or read.

**`STORAGE_PATH` sits outside every web root and outside the repo.** nginx must have no `location` that can reach it. Elvee serves `src/public` statically — that pattern must **not** be copied for KYC.

## 3. Upload validation (in this order, fail closed)

1. Authenticated + authorised for the owning entity.
2. `DocumentTypes` row exists and is active → gives `allowed_mime` and `max_size_mb`.
3. Size checked by multer limits **before** buffering the whole file; over limit → 422 with the actual limit in the message.
4. Extension allowlist derived from `allowed_mime` (`pdf`, `jpg`, `jpeg`, `png` for KYC — no `svg`: it executes script; no archives; no Office macros unless a type explicitly needs it).
5. **Magic-byte sniff of the actual content**, not the client-declared `Content-Type` header. Mismatch → 422. A `.pdf` that is really an HTML file is a stored-XSS vector when someone opens it.
6. SHA-256 computed and stored in `checksum_sha256` — proves integrity after a restore and detects duplicate re-uploads.
7. Only then persist the row; if the DB write fails, the orphaned file is removed in the same request's `catch`.

## 4. Download — the only way to read a private file

`GET /api/v1/documents/:id/download`
- Resolves the document row, then authorises: owning member, or an admin with `member.view` (member docs) / `application.view` (application docs). Anyone else → **404**, not 403.
- Streams from the adapter with `Content-Disposition: attachment; filename="<original_name>"`, the stored MIME, `X-Content-Type-Options: nosniff`, and `Cache-Control: private, no-store`.
- Writes an `AuditLogs` row (`document.downloaded`) with actor and document id.
- Never returns a filesystem path, key or bucket name to the client.

Post-MVP option: short-lived signed URLs (CloudFront/S3) — only with an expiry ≤5 min and the same authorisation check before signing. Not in MVP scope.

## 5. Lifecycle

| Event | Behaviour |
|---|---|
| Re-upload of the same document type | New row, `version = previous + 1`. Old file is **kept** — approval history must be able to show what the approver actually saw |
| Member deletes an unverified document | Soft-delete the row; file removed by a retention job after 30 days |
| Verified document | Immutable. Cannot be deleted by the member; replacing it creates a new version |
| Member/application soft-deleted | Files retained; retention answered by OQ-15 (rejected-applicant document retention) |
| Invoice/receipt PDF | Regenerable from data; the stored number never changes |

## 6. Open items

| ID | Item | Class |
|---|---|---|
| OQ-10c | `local` vs `s3` for production, and the volume/bucket that holds it | NEEDS DECISION (before staging; not blocking M0) |
| OQ-15 | Retention for documents of rejected/withdrawn applicants | NEEDS DECISION (before go-live) |
| OQ-17 | ClamAV (or equivalent) scanning of uploads before they are readable by an admin | RECOMMENDATION — members upload arbitrary files that staff then open |
| OQ-19 | Per-member storage quota / total upload cap | RECOMMENDATION (disk-exhaustion defence; `observability.md` §6 alerts at 85 %) |

## 7. Backup coupling

Uploads and the database are backed up as a pair, uploads **after** the DB dump (`backup-recovery.md` §2/§5). A restored DB whose `file_path` values point at missing files is a broken system, and no code path can regenerate a member's trade licence.

## 8. Sentinel assertions

Upload success writes a row + a file with a UUID name · oversize → 422 with the real limit · declared-PDF-but-actually-HTML → 422 · direct URL fetch of a KYC path → 404 · download by a different member → 404 · download by a permitted admin → 200 + audit row · re-upload produces version 2 with both files present · path traversal in the original filename lands inside `STORAGE_PATH` with a UUID name.
