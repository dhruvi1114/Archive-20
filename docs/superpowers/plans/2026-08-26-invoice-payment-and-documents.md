# Invoice Payment, Listing & Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a member pay their own membership invoice from the customer portal (no payment gateway — a confirm-and-flip, same transaction the admin's "Mark as paid" already runs), see their invoices and a real GST invoice PDF, see a real receipt PDF once paid, and let admin staff see every invoice across all members in one list — with the association's own invoice/receipt document rendered in a real, downloadable PDF.

**Architecture:** All invoice/payment logic stays inside the existing `backend/src/modules/member` module (repository/service/controller/routes) — that is where `recordInvoicePayment` already lives, and this plan follows that convention rather than inventing a new `modules/invoice` split that nothing else in the codebase uses yet. One new table, `Receipts`, is added by migration — it is *only* a numbered record of a payment for the PDF and for audit; there is still no `Payments`/gateway table, consistent with the earlier decision to keep the pay action a simple status flip, not a payment-provider integration. PDFs are generated server-side with `pdfkit` (pure JS, no headless browser, no native deps) and stored through the existing `@helpers/storage` adapter — the same one KYC documents already use — and served through a dual-audience download route modelled exactly on `documentRouter`'s existing `/:id/download`.

**Tech Stack:** Express + TypeScript + Prisma + PostgreSQL (backend); Next.js + TypeScript (customer); React + TypeScript + Ant Design (admin); `pdfkit` (new dependency, backend only); Vitest for backend tests.

**Spec:** `docs/billing-payment.md`, `docs/approval-workflow.md` §5, `docs/modules/M5-payments-finance.md`, `docs/rbac.md` §3 (`invoice.view`, `invoice.manage`, `payment.record`), `.claude/skills/association-admin-ui/` (admin UI components).

## Global Constraints

- Prisma migrations only — never rely on schema auto-sync, never edit an already-applied migration (`CLAUDE.md`).
- Every schema change needs proper FKs, constraints, indexes, and DB transactions for multi-row writes (`CLAUDE.md`).
- Customer UX and Admin UX are separate design systems — do not share components between `customer/` and `admin/` (`CLAUDE.md`).
- Every admin screen this plan touches or adds must use the shared components catalogued in `.claude/skills/association-admin-ui/` (table, search, cells, tokens) — do not reach for a raw Ant Design component directly.
- No accounting-system integration — out of scope, parked (`CLAUDE.md`).
- No payment gateway, no `Payments`/webhook table — the pay action stays a confirm-and-flip (decided earlier in this project).
- Money is `Decimal`, never a client-trusted number — totals are recomputed/read server-side (`billing-payment.md`).
- The association's GSTIN (`organisation.gstin`) and at least one active `FeeStructure` row must be present for the invoice PDF to be legally correct — both are already set in this environment (verified: GSTIN `29ABCDE1234F1Z5`; fee id 3, ₹20,000 + 18% GST, active). If either becomes blank again, invoice/receipt PDF generation must still work mechanically but the printed GSTIN block will legitimately read "Not GST registered" rather than fail.

---

## File Structure

**Backend — new/changed:**
- `backend/prisma/migrations/<timestamp>_add_receipts/migration.sql` — new `Receipts` table (Prisma-generated, task 1)
- `backend/prisma/schema/application.prisma` — add `Receipt` model (task 1)
- `backend/src/helpers/pdf/invoiceTemplate.ts` — renders an `Invoice` + items + member + org settings to a PDF buffer (task 2)
- `backend/src/helpers/pdf/receiptTemplate.ts` — renders a `Receipt` + its `Invoice` to a PDF buffer (task 2)
- `backend/src/modules/member/member.repository.ts` — add `createReceipt`, `findReceiptByInvoiceId`, `listInvoicesAdmin` (tasks 3, 6)
- `backend/src/modules/member/member.service.ts` — refactor `recordInvoicePayment` into a shared `applyInvoicePayment` helper; add `payOwnInvoice`; add `getInvoicePdf`, `getReceiptPdf`, `listInvoicesAdmin` (tasks 3, 4, 6)
- `backend/src/modules/member/member.types.ts` — add `ownInvoicePaymentParamsSchema`, `listInvoicesSchema` (tasks 3, 6)
- `backend/src/modules/member/member.controller.ts` — add `payOwnInvoice`, `downloadInvoicePdf`, `downloadReceiptPdf`, `listInvoicesAdmin` (tasks 3, 4, 6)
- `backend/src/modules/member/member.routes.ts` — new routes on `memberRouter` (self-pay) and a new shared `invoiceRouter` (PDF downloads, both audiences), plus one on `memberAdminRouter` (admin list) (tasks 3, 4, 6)
- `backend/src/constant/audit.constant.ts` — add `RECEIPT_ISSUED` action (task 1)
- `backend/src/routes/index.ts` — mount the new `invoiceRouter` (task 4)
- Tests: `backend/src/modules/member/member.invoicePayment.test.ts`, `backend/src/helpers/pdf/pdfTemplates.test.ts`, `backend/src/modules/member/member.invoiceList.test.ts` (tasks 3, 2, 6)

**Customer — new/changed:**
- `customer/src/types/member.ts` — add `MemberInvoice`, `MemberReceipt` types + `invoices` field + normalisers (task 5)
- `customer/src/constants/endpoints.ts` — add invoice endpoints (task 5)
- `customer/src/services/MemberService.ts` — add `payInvoice`, `downloadInvoicePdf`, `downloadReceiptPdf` (task 5)
- `customer/src/components/application/ApplicationView.tsx` — pass `reloadMember` down (task 7)
- `customer/src/components/application/ApplicationTracker.tsx` — wire the "Pay to activate" button (task 7)
- `customer/src/components/billing/InvoiceList.tsx` — new client component, the real Billing screen (task 8)
- `customer/src/app/(member)/invoices/page.tsx` — replace the placeholder (task 8)

**Admin — new/changed:**
- `admin/src/services/invoicesService.ts` — new, list + PDF download links (task 9)
- `admin/src/pages/billing/Invoices.tsx` — new, the real Money → Invoices screen (task 9)
- `admin/src/routes/AppRoutes.tsx` — real route for `/billing/invoices`, excluded from the placeholder loop (task 9)
- `admin/src/constant/navigation.tsx` — fix the `invoices` nav item's `module` tag from `M4` to `M5` (task 9)
- `admin/src/pages/members/ProfileTab.tsx` — add PDF download links next to each invoice (task 10)

---

### Task 1: `Receipts` table (migration)

**Files:**
- Modify: `backend/prisma/schema/application.prisma`
- Modify: `backend/src/constant/audit.constant.ts`
- Create (generated): `backend/prisma/migrations/<timestamp>_add_receipts/migration.sql`

**Interfaces:**
- Produces: Prisma model `Receipt { id, receipt_number, invoice_id, member_id, amount, paid_at, pdf_path, createdAt }`, unique on `invoice_id` (one receipt per invoice — this plan never issues partial receipts) and on `receipt_number`.

- [ ] **Step 1: Add the `Receipt` model**

Add to `backend/prisma/schema/application.prisma`, directly below the `Invoice` model (after line 721, before `InvoiceItem`):

```prisma
/// Proof of payment for one invoice. One per invoice — this build only ever
/// pays an invoice in full, in one click, so there is nothing to split.
model Receipt {
  /// Surrogate key.
  id BigInt @id @default(autoincrement())

  /// Human-facing number, format RC + year + calendar quarter + 3-digit
  /// sequence restarting each quarter, e.g. RC202603001 — same shape as
  /// `Invoice.invoice_number` (client decision, 2026-08-13), different prefix.
  receipt_number String @unique @db.VarChar(30)

  /// FK to Invoices.id — the invoice this receipt is for. ON DELETE RESTRICT:
  /// a receipt is a financial record and is never orphaned. One receipt per
  /// invoice, enforced by the unique constraint below.
  invoice_id BigInt @unique

  /// FK to Members.id — who paid. Denormalised off the invoice so a receipt
  /// still names the payer even if the invoice's own member link is ever
  /// changed (it isn't, today, but the column exists to make that impossible
  /// to get wrong).
  member_id BigInt

  /// Amount received, INR, 2dp. Always the invoice's total_amount today —
  /// this build has no partial payments.
  amount Decimal @db.Decimal(14, 2)

  /// When the payment was recorded.
  paid_at DateTime @default(now()) @db.Timestamptz(6)

  /// Storage key of the rendered PDF, through `@helpers/storage` — same
  /// adapter as KYC documents and invoice PDFs.
  pdf_path String? @db.Text

  /// Row creation timestamp (UTC).
  createdAt DateTime @default(now()) @db.Timestamptz(6)

  /// The invoice this receipt closes out.
  invoice Invoice @relation(fields: [invoice_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  /// Who paid.
  member Member @relation(fields: [member_id], references: [id], onDelete: Restrict, onUpdate: Cascade)

  @@index([member_id, paid_at(sort: Desc)])
  @@map("Receipts")
}
```

Add the back-relations so Prisma's schema stays consistent:
- In `model Invoice` (application.prisma, inside the relations block near `items InvoiceItem[]`), add:
  ```prisma
  /// The receipt issued when this invoice was paid, if it has been.
  receipt Receipt?
  ```
- In `model Member` (`member.prisma`, near the existing `invoices Invoice[]` relation), add:
  ```prisma
  receipts Receipt[]
  ```

- [ ] **Step 2: Add the audit action**

In `backend/src/constant/audit.constant.ts`, next to `INVOICE_PAID: 'invoice.paid',` (line 203), add:

```typescript
  /** A receipt was generated for a paid invoice. */
  RECEIPT_ISSUED: 'receipt.issued',
```

- [ ] **Step 3: Generate and review the migration**

Run: `cd backend && npm run prisma:migrate:create -- --name add_receipts`

Expected: a new file under `backend/prisma/migrations/<timestamp>_add_receipts/migration.sql` containing `CREATE TABLE "Receipts" (...)`, a `UNIQUE` constraint on `invoice_id` and on `receipt_number`, two `FOREIGN KEY` clauses (`RESTRICT`), and the `member_id, paid_at` index. Read the generated SQL before continuing — this is the only chance to catch a wrong `ON DELETE` behaviour before it is applied.

- [ ] **Step 4: Apply it and regenerate the client**

Run: `cd backend && npm run prisma:migrate && npm run prisma:generate`
Expected: migration applies cleanly against `local_db`; `@prisma/client` now exports `prisma.receipt`.

- [ ] **Step 5: Commit**

```bash
git add backend/prisma/schema/application.prisma backend/prisma/schema/member.prisma backend/prisma/migrations backend/src/constant/audit.constant.ts
git commit -m "feat(db): add Receipts table for paid-invoice proof of payment"
```

---

### Task 2: PDF templates (invoice + receipt)

**Files:**
- Create: `backend/src/helpers/pdf/invoiceTemplate.ts`
- Create: `backend/src/helpers/pdf/receiptTemplate.ts`
- Test: `backend/src/helpers/pdf/pdfTemplates.test.ts`
- Modify: `backend/package.json` (add `pdfkit` + `@types/pdfkit`)

**Interfaces:**
- Consumes: `Invoice` row + `InvoiceItem[]` + `Member` row + org settings map (`{name, legal_name, gstin, address}`) from `SystemSettings`.
- Produces: `renderInvoicePdf(input: InvoiceTemplateInput): Promise<Buffer>` and `renderReceiptPdf(input: ReceiptTemplateInput): Promise<Buffer>` — both used by `member.service.ts` in task 4.

- [ ] **Step 1: Install `pdfkit`**

Run: `cd backend && npm install pdfkit && npm install -D @types/pdfkit`

- [ ] **Step 2: Write the failing test**

Create `backend/src/helpers/pdf/pdfTemplates.test.ts`:

```typescript
import { describe, expect, it } from 'vitest';
import { renderInvoicePdf } from './invoiceTemplate';
import { renderReceiptPdf } from './receiptTemplate';

const ORG = {
  name: 'ILGDA',
  legal_name: 'India Lab-Grown Diamond Association',
  gstin: '29ABCDE1234F1Z5',
  address: '12 MG Road, Bengaluru, KA 560001',
};

const MEMBER = {
  company_name: 'Riya Diamonds Pvt Ltd',
  legal_name: 'Riya Diamonds Private Limited',
  gst_number: '27AAACR1234M1Z1',
  address: '4th Floor, Diamond Bourse, Mumbai, MH 400001',
};

const INVOICE = {
  invoice_number: 'IN202603001',
  issue_date: new Date('2026-08-26'),
  due_date: new Date('2026-09-10'),
  subtotal: '20000.00',
  tax_amount: '3600.00',
  total_amount: '23600.00',
  currency: 'INR',
};

const ITEMS = [
  {
    description: 'New membership — Manufacturer category',
    quantity: '1',
    unit_price: '20000.00',
    tax_rate: '18.00',
    tax_amount: '3600.00',
    line_total: '23600.00',
  },
];

describe('renderInvoicePdf', () => {
  it('produces a non-empty PDF buffer starting with the PDF magic bytes', async () => {
    const buffer = await renderInvoicePdf({ org: ORG, member: MEMBER, invoice: INVOICE, items: ITEMS });

    expect(buffer.byteLength).toBeGreaterThan(500);
    expect(buffer.subarray(0, 5).toString('ascii')).toBe('%PDF-');
  });
});

describe('renderReceiptPdf', () => {
  it('produces a non-empty PDF buffer starting with the PDF magic bytes', async () => {
    const buffer = await renderReceiptPdf({
      org: ORG,
      member: MEMBER,
      invoice: INVOICE,
      receipt: { receipt_number: 'RC202603001', amount: '23600.00', paid_at: new Date('2026-08-26') },
    });

    expect(buffer.byteLength).toBeGreaterThan(300);
    expect(buffer.subarray(0, 5).toString('ascii')).toBe('%PDF-');
  });
});
```

- [ ] **Step 3: Run it, confirm it fails**

Run: `cd backend && npx vitest run src/helpers/pdf/pdfTemplates.test.ts`
Expected: FAIL — `Cannot find module './invoiceTemplate'` (files do not exist yet).

- [ ] **Step 4: Write `invoiceTemplate.ts`**

Create `backend/src/helpers/pdf/invoiceTemplate.ts`:

```typescript
import PDFDocument from 'pdfkit';

/**
 * The one place the invoice's printed layout lives. Every GST-relevant field
 * (both GSTINs, the tax line, the line-item breakdown) is drawn explicitly
 * because a tax invoice missing any one of them is a compliance problem, not
 * a cosmetic one (billing-payment.md §7, OQ-8).
 */

export interface OrgInfo {
  name: string;
  legal_name: string;
  /** Empty string means "not GST registered" — printed as such, not omitted. */
  gstin: string;
  address: string;
}

export interface MemberInfo {
  company_name: string;
  legal_name: string | null;
  gst_number: string | null;
  address: string | null;
}

export interface InvoiceInfo {
  invoice_number: string;
  issue_date: Date;
  due_date: Date;
  subtotal: string;
  tax_amount: string;
  total_amount: string;
  currency: string;
}

export interface InvoiceLineItem {
  description: string;
  quantity: string;
  unit_price: string;
  tax_rate: string;
  tax_amount: string;
  line_total: string;
}

export interface InvoiceTemplateInput {
  org: OrgInfo;
  member: MemberInfo;
  invoice: InvoiceInfo;
  items: InvoiceLineItem[];
}

const money = (value: string, currency: string) => `${currency} ${Number(value).toFixed(2)}`;
const date = (value: Date) =>
  value.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });

export const renderInvoicePdf = (input: InvoiceTemplateInput): Promise<Buffer> =>
  new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 50 });
    const chunks: Buffer[] = [];

    doc.on('data', (chunk: Buffer) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    doc.fontSize(18).text(input.org.name, { continued: false });
    doc.fontSize(9).fillColor('#555').text(input.org.legal_name).text(input.org.address);
    doc
      .text(input.org.gstin ? `GSTIN: ${input.org.gstin}` : 'Not GST registered')
      .fillColor('#000');

    doc.moveDown(1.5).fontSize(14).text('TAX INVOICE', { align: 'right' });
    doc
      .fontSize(10)
      .text(`Invoice No: ${input.invoice.invoice_number}`, { align: 'right' })
      .text(`Issue date: ${date(input.invoice.issue_date)}`, { align: 'right' })
      .text(`Due date: ${date(input.invoice.due_date)}`, { align: 'right' });

    doc.moveDown(1.5).fontSize(11).text('Bill to');
    doc
      .fontSize(10)
      .text(input.member.legal_name ?? input.member.company_name)
      .text(input.member.address ?? '—')
      .text(input.member.gst_number ? `GSTIN: ${input.member.gst_number}` : 'No GSTIN on file');

    doc.moveDown(1.5);
    const tableTop = doc.y;
    doc
      .fontSize(9)
      .text('Description', 50, tableTop)
      .text('Qty', 280, tableTop)
      .text('Unit price', 330, tableTop)
      .text('Tax %', 410, tableTop)
      .text('Line total', 470, tableTop);
    doc.moveTo(50, tableTop + 15).lineTo(545, tableTop + 15).stroke();

    let y = tableTop + 22;
    input.items.forEach((item) => {
      doc
        .fontSize(9)
        .text(item.description, 50, y, { width: 220 })
        .text(item.quantity, 280, y)
        .text(money(item.unit_price, input.invoice.currency), 330, y)
        .text(`${item.tax_rate}%`, 410, y)
        .text(money(item.line_total, input.invoice.currency), 470, y);
      y += 20;
    });

    doc.moveTo(50, y + 5).lineTo(545, y + 5).stroke();
    y += 15;
    doc.fontSize(10).text(`Subtotal: ${money(input.invoice.subtotal, input.invoice.currency)}`, 350, y, {
      align: 'right',
    });
    y += 15;
    doc.text(`Tax: ${money(input.invoice.tax_amount, input.invoice.currency)}`, 350, y, {
      align: 'right',
    });
    y += 15;
    doc
      .fontSize(12)
      .text(`Total: ${money(input.invoice.total_amount, input.invoice.currency)}`, 350, y, {
        align: 'right',
      });

    doc.end();
  });
```

- [ ] **Step 5: Write `receiptTemplate.ts`**

Create `backend/src/helpers/pdf/receiptTemplate.ts`:

```typescript
import PDFDocument from 'pdfkit';
import type { MemberInfo, OrgInfo } from './invoiceTemplate';

export interface ReceiptInfo {
  receipt_number: string;
  amount: string;
  paid_at: Date;
}

export interface ReceiptTemplateInput {
  org: OrgInfo;
  member: MemberInfo;
  invoice: { invoice_number: string; currency: string };
  receipt: ReceiptInfo;
}

const money = (value: string, currency: string) => `${currency} ${Number(value).toFixed(2)}`;
const date = (value: Date) =>
  value.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });

export const renderReceiptPdf = (input: ReceiptTemplateInput): Promise<Buffer> =>
  new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 50 });
    const chunks: Buffer[] = [];

    doc.on('data', (chunk: Buffer) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    doc.fontSize(18).text(input.org.name);
    doc.fontSize(9).fillColor('#555').text(input.org.legal_name).text(input.org.address).fillColor('#000');

    doc.moveDown(1.5).fontSize(16).text('PAYMENT RECEIPT', { align: 'center' });
    doc.moveDown(1);

    doc
      .fontSize(11)
      .text(`Receipt No: ${input.receipt.receipt_number}`)
      .text(`Against Invoice: ${input.invoice.invoice_number}`)
      .text(`Paid on: ${date(input.receipt.paid_at)}`)
      .text(`Received from: ${input.member.legal_name ?? input.member.company_name}`);

    doc.moveDown(1);
    doc
      .fontSize(14)
      .text(`Amount received: ${money(input.receipt.amount, input.invoice.currency)}`, { align: 'left' });

    doc.moveDown(2).fontSize(9).fillColor('#555').text('This is a system-generated receipt.');

    doc.end();
  });
```

- [ ] **Step 6: Run the test again**

Run: `cd backend && npx vitest run src/helpers/pdf/pdfTemplates.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add backend/package.json backend/package-lock.json backend/src/helpers/pdf
git commit -m "feat(pdf): add invoice and receipt PDF templates"
```

---

### Task 3: Self-service pay endpoint (refactor + new route)

**Files:**
- Modify: `backend/src/modules/member/member.service.ts:617-677`
- Modify: `backend/src/modules/member/member.types.ts`
- Modify: `backend/src/modules/member/member.controller.ts`
- Modify: `backend/src/modules/member/member.routes.ts`
- Test: `backend/src/modules/member/member.invoicePayment.test.ts`

**Interfaces:**
- Consumes: `Receipt` model from task 1 (`prisma.receipt.create`), `memberAudit`/`adminAudit` helpers already in `member.service.ts:52-60`.
- Produces: `service.payOwnInvoice(memberId: bigint, invoiceId: bigint, actor: Actor): Promise<{invoice, member, receipt}>` — task 4's PDF endpoints and task 5/7's frontend both depend on the route this task adds, `POST /v1/members/me/invoices/:invoiceId/pay`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/member/member.invoicePayment.test.ts`:

```typescript
import { beforeEach, describe, expect, it, vi } from 'vitest';

const invoiceFindFirst = vi.fn();
const invoiceUpdate = vi.fn();
const membershipTermUpdateMany = vi.fn();
const receiptCreate = vi.fn();
const auditLogCreate = vi.fn();
const findMemberById = vi.fn();
const updateMember = vi.fn();
const recordStatusChange = vi.fn();

const tx = {
  invoice: { update: invoiceUpdate },
  membershipTerm: { updateMany: membershipTermUpdateMany },
  receipt: { create: receiptCreate },
  auditLog: { create: auditLogCreate },
};

vi.mock('@db/prisma', () => ({
  prisma: {
    invoice: { findFirst: (...a: unknown[]) => invoiceFindFirst(...a) },
    $transaction: (fn: (tx: unknown) => unknown) => fn(tx),
  },
}));

vi.mock('@modules/member/member.repository', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@modules/member/member.repository')>();
  return {
    ...actual,
    findMemberById: (...a: unknown[]) => findMemberById(...a),
    updateMember: (...a: unknown[]) => updateMember(...a),
    recordStatusChange: (...a: unknown[]) => recordStatusChange(...a),
  };
});

const { payOwnInvoice, recordInvoicePayment } = await import('@modules/member/member.service');

const ACTOR = { id: 9n, ip: '127.0.0.1', userAgent: 'vitest', requestId: 'req-1' };

const OPEN_INVOICE = {
  id: 42n,
  member_id: 5n,
  invoice_number: 'IN202603001',
  status: 'ISSUED',
  total_amount: { toFixed: () => '23600.00' },
  amount_paid: { toFixed: () => '0.00' },
};

describe('payOwnInvoice', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    invoiceFindFirst.mockResolvedValue(OPEN_INVOICE);
    findMemberById.mockResolvedValue({ id: 5n, status: 'PENDING', joined_on: null });
    updateMember.mockResolvedValue({ id: 5n, status: 'ACTIVE' });
    invoiceUpdate.mockResolvedValue({ id: 42n, status: 'PAID' });
    receiptCreate.mockResolvedValue({ id: 1n, receipt_number: 'RC202603001' });
  });

  it('rejects an invoice that does not belong to the caller', async () => {
    invoiceFindFirst.mockResolvedValue(null);

    await expect(payOwnInvoice(5n, 42n, ACTOR)).rejects.toMatchObject({
      messageKey: 'member.invoiceNotFound',
    });
  });

  it('rejects an invoice already paid', async () => {
    invoiceFindFirst.mockResolvedValue({ ...OPEN_INVOICE, status: 'PAID' });

    await expect(payOwnInvoice(5n, 42n, ACTOR)).rejects.toMatchObject({
      messageKey: 'member.invoiceAlreadyPaid',
    });
  });

  it('activates a PENDING member without attributing the change to an admin', async () => {
    await payOwnInvoice(5n, 42n, ACTOR);

    expect(recordStatusChange).toHaveBeenCalledWith(
      tx,
      expect.objectContaining({ changed_by_admin_id: null }),
    );
  });

  it('writes the audit row as MEMBER, not ADMIN', async () => {
    await payOwnInvoice(5n, 42n, ACTOR);

    expect(auditLogCreate).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ actor_type: 'MEMBER' }) }),
    );
  });

  it('creates exactly one receipt row for the paid amount', async () => {
    await payOwnInvoice(5n, 42n, ACTOR);

    expect(receiptCreate).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ invoice_id: 42n, member_id: 5n }),
      }),
    );
  });
});

describe('recordInvoicePayment (admin path, unchanged behaviour)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    invoiceFindFirst.mockResolvedValue(OPEN_INVOICE);
    findMemberById.mockResolvedValue({ id: 5n, status: 'PENDING', joined_on: null });
    updateMember.mockResolvedValue({ id: 5n, status: 'ACTIVE' });
    invoiceUpdate.mockResolvedValue({ id: 42n, status: 'PAID' });
    receiptCreate.mockResolvedValue({ id: 1n, receipt_number: 'RC202603001' });
  });

  it('still attributes the status change to the acting admin', async () => {
    await recordInvoicePayment(5n, 42n, ACTOR);

    expect(recordStatusChange).toHaveBeenCalledWith(
      tx,
      expect.objectContaining({ changed_by_admin_id: 9n }),
    );
  });

  it('still writes the audit row as ADMIN', async () => {
    await recordInvoicePayment(5n, 42n, ACTOR);

    expect(auditLogCreate).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ actor_type: 'ADMIN' }) }),
    );
  });
});
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd backend && npx vitest run src/modules/member/member.invoicePayment.test.ts`
Expected: FAIL — `payOwnInvoice` is not exported yet, and the current `recordInvoicePayment` neither creates a receipt nor mocks cleanly against `tx.receipt.create`.

- [ ] **Step 3: Refactor `member.service.ts`**

Replace lines 617-677 of `backend/src/modules/member/member.service.ts` (the current `recordInvoicePayment`) with:

```typescript
const nextReceiptNumber = async (tx: Prisma.TransactionClient): Promise<string> => {
  const now = new Date();
  const quarter = Math.floor(now.getUTCMonth() / 3) + 1;
  const prefix = `RC${now.getUTCFullYear()}${String(quarter).padStart(2, '0')}`;
  const count = await tx.receipt.count({ where: { receipt_number: { startsWith: prefix } } });

  return `${prefix}${String(count + 1).padStart(3, '0')}`;
};

interface PaymentAttribution {
  /** NULL for a self-service payment (`member.repository.ts`'s "system did it" convention). */
  changedByAdminId: bigint | null;
  audit: ReturnType<typeof adminAudit> | ReturnType<typeof memberAudit>;
}

/**
 * The one transaction both payment paths share: invoice → PAID, its
 * membership term(s) → ACTIVE, the member → ACTIVE if this was their first
 * payment, a receipt issued, and an audit row — all or nothing.
 *
 * `recordInvoicePayment` (admin, offline payment) and `payOwnInvoice`
 * (member, self-service) differ only in who gets credited for the status
 * change and how the audit row is attributed — see `PaymentAttribution`.
 */
const applyInvoicePayment = async (
  memberId: bigint,
  invoiceId: bigint,
  attribution: PaymentAttribution,
) => {
  const invoice = await prisma.invoice.findFirst({
    where: { id: invoiceId, member_id: memberId, deletedAt: null },
  });
  if (!invoice) throw notFound('member.invoiceNotFound');

  if (invoice.status === InvoiceStatus.PAID) {
    throw conflict('member.invoiceAlreadyPaid');
  }
  if (invoice.status === InvoiceStatus.DRAFT || invoice.status === InvoiceStatus.CANCELLED) {
    throw conflict('member.invoiceNotPayable');
  }

  const member = await repo.findMemberById(prisma, memberId);
  if (!member) throw notFound('member.notFound');

  return prisma.$transaction(async (tx) => {
    const paidInvoice = await tx.invoice.update({
      where: { id: invoiceId },
      data: {
        status: InvoiceStatus.PAID,
        amount_paid: invoice.total_amount,
        balance_due: new Prisma.Decimal(0),
      },
    });

    // Every term this invoice was raised for goes live together — a member
    // does not hold a mix of active and still-pending terms off one payment.
    await tx.membershipTerm.updateMany({
      where: { invoice_id: invoiceId, status: TermStatus.PENDING_PAYMENT },
      data: { status: TermStatus.ACTIVE },
    });

    let updatedMember = member;
    if (member.status === MemberStatus.PENDING) {
      updatedMember = await repo.updateMember(tx, memberId, {
        status: MemberStatus.ACTIVE,
        ...(member.joined_on ? {} : { joined_on: new Date() }),
      });

      await repo.recordStatusChange(tx, {
        member_id: memberId,
        from_status: member.status,
        to_status: MemberStatus.ACTIVE,
        reason: `Invoice ${invoice.invoice_number} paid`,
        changed_by_admin_id: attribution.changedByAdminId,
      });
    }

    const receipt = await tx.receipt.create({
      data: {
        receipt_number: await nextReceiptNumber(tx),
        invoice_id: invoiceId,
        member_id: memberId,
        amount: invoice.total_amount,
      },
    });

    await writeAudit(tx, {
      ...attribution.audit,
      action: AUDIT_ACTIONS.INVOICE_PAID,
      entityName: 'Invoices',
      entityId: invoiceId,
      before: { status: invoice.status, amount_paid: invoice.amount_paid.toFixed(2) },
      after: { status: InvoiceStatus.PAID, amount_paid: invoice.total_amount.toFixed(2) },
    });

    return { invoice: paidInvoice, member: updatedMember, receipt };
  });
};

/** Staff recording an offline payment (ACCOUNTS, `payment.record`). */
export const recordInvoicePayment = (memberId: bigint, invoiceId: bigint, actor: Actor) =>
  applyInvoicePayment(memberId, invoiceId, {
    changedByAdminId: actor.id,
    audit: adminAudit(actor),
  });

/** Self-service: a member paying their own invoice from the portal. */
export const payOwnInvoice = (memberId: bigint, invoiceId: bigint, actor: Actor) =>
  applyInvoicePayment(memberId, invoiceId, {
    changedByAdminId: null,
    audit: memberAudit(actor),
  });
```

This is a like-for-like refactor of the existing function plus the new receipt row — nothing about the admin path's externally-visible behaviour changes except that a `Receipt` row now also gets created (needed for task 4's PDF).

- [ ] **Step 4: Add the self-service params schema**

In `backend/src/modules/member/member.types.ts`, next to `invoicePaymentParamsSchema` (line 122), add:

```typescript
export const ownInvoicePaymentParamsSchema = z.object({
  invoiceId: z.string().regex(/^\d+$/, 'validation.invalidId'),
});
```

- [ ] **Step 5: Add the controller handler**

In `backend/src/modules/member/member.controller.ts`, next to `recordInvoicePayment` (after line 370), add:

```typescript
export const payOwnInvoice = handler(async (req, res) => {
  const member = await ownMember(req);
  const updated = await service.payOwnInvoice(
    member.id,
    BigInt(req.params.invoiceId as string),
    actor(req),
  );

  handleApiResponse(res, {
    responseType: RES_STATUS.ACTION,
    messageKey: 'member.invoicePaid',
    data: serialise(updated),
  });
});
```

- [ ] **Step 6: Wire the route**

In `backend/src/modules/member/member.routes.ts`, add `ownInvoicePaymentParamsSchema` to the import from `@modules/member/member.types` (line 8-19), then add, right after the `/me/documents` block (after line 89):

```typescript
memberRouter.post(
  '/me/invoices/:invoiceId/pay',
  validateRequest({ params: ownInvoicePaymentParamsSchema }),
  controller.payOwnInvoice,
);
```

- [ ] **Step 7: Run the test, confirm it passes**

Run: `cd backend && npx vitest run src/modules/member/member.invoicePayment.test.ts`
Expected: PASS (7 tests).

- [ ] **Step 8: Run the full backend suite**

Run: `cd backend && npm test`
Expected: PASS — the admin `recordInvoicePayment` call sites (member.routes.ts, any existing self-test suites) are unaffected since its signature and behaviour are unchanged.

- [ ] **Step 9: Commit**

```bash
git add backend/src/modules/member
git commit -m "feat(invoice): self-service invoice payment for members, shared with the admin path"
```

---

### Task 4: PDF download endpoints (invoice + receipt, both audiences)

**Files:**
- Modify: `backend/src/modules/member/member.service.ts`
- Modify: `backend/src/modules/member/member.controller.ts`
- Modify: `backend/src/modules/member/member.routes.ts`
- Modify: `backend/src/routes/index.ts`

**Interfaces:**
- Consumes: `renderInvoicePdf`/`renderReceiptPdf` (task 2), `storage` + `buildStorageKey` (`@helpers/storage`, already used by `document.service.ts`), `AUDIT_ACTIONS.RECEIPT_ISSUED` (task 1), `SystemSettings` rows for `organisation.*`.
- Produces: `GET /v1/invoices/:invoiceId/pdf` and `GET /v1/invoices/:invoiceId/receipt/pdf`, dual-audience like `documentRouter`'s `/:id/download` — task 5/9's frontends link to these directly.

- [ ] **Step 1: Add the service functions**

In `backend/src/modules/member/member.service.ts`, add near the bottom (after `payOwnInvoice`):

```typescript
import { renderInvoicePdf } from '@helpers/pdf/invoiceTemplate';
import { renderReceiptPdf } from '@helpers/pdf/receiptTemplate';
import { buildStorageKey, storage } from '@helpers/storage';
import * as settingsService from '@modules/settings/settings.service';

const orgInfo = async () => {
  const settings = await settingsService.getPublicSettings();
  return {
    name: settings['organisation.name'] ?? 'Association',
    legal_name: settings['organisation.legal_name'] ?? settings['organisation.name'] ?? 'Association',
    gstin: settings['organisation.gstin'] ?? '',
    address: settings['organisation.address'] ?? '',
  };
};

/**
 * Generates the invoice PDF on first request and caches it in storage —
 * an ISSUED invoice's line items never change (`billing-payment.md` §2:
 * "only DRAFT invoices are editable"), so the rendered PDF is stable too.
 */
export const getInvoicePdf = async (
  invoiceId: bigint,
  viewer: { memberId: bigint | null; isAdmin: boolean },
) => {
  const invoice = await prisma.invoice.findFirst({
    where: { id: invoiceId, deletedAt: null },
    include: { items: { orderBy: { sort_order: 'asc' } }, member: true },
  });
  if (!invoice) throw notFound('member.invoiceNotFound');

  const isOwner = viewer.memberId !== null && viewer.memberId === invoice.member_id;
  if (!isOwner && !viewer.isAdmin) throw notFound('member.invoiceNotFound');

  if (invoice.pdf_path && (await storage.current.exists(invoice.pdf_path))) {
    return { stream: await storage.current.getStream(invoice.pdf_path), filename: `${invoice.invoice_number}.pdf` };
  }

  const buffer = await renderInvoicePdf({
    org: await orgInfo(),
    member: {
      company_name: invoice.member.company_name,
      legal_name: invoice.member.legal_name,
      gst_number: invoice.member.gst_number,
      address: null,
    },
    invoice: {
      invoice_number: invoice.invoice_number,
      issue_date: invoice.issue_date,
      due_date: invoice.due_date,
      subtotal: invoice.subtotal.toFixed(2),
      tax_amount: invoice.tax_amount.toFixed(2),
      total_amount: invoice.total_amount.toFixed(2),
      currency: invoice.currency,
    },
    items: invoice.items.map((item) => ({
      description: item.description,
      quantity: item.quantity.toFixed(2),
      unit_price: item.unit_price.toFixed(2),
      tax_rate: item.tax_rate.toFixed(2),
      tax_amount: item.tax_amount.toFixed(2),
      line_total: item.line_total.toFixed(2),
    })),
  });

  const key = buildStorageKey(['invoices', String(invoice.id)], `${invoice.invoice_number}.pdf`);
  await storage.current.put(key, buffer, { mime: 'application/pdf', size: buffer.byteLength });
  await prisma.invoice.update({ where: { id: invoice.id }, data: { pdf_path: key } });

  return { stream: await storage.current.getStream(key), filename: `${invoice.invoice_number}.pdf` };
};

export const getReceiptPdf = async (
  invoiceId: bigint,
  viewer: { memberId: bigint | null; isAdmin: boolean },
) => {
  const receipt = await prisma.receipt.findFirst({
    where: { invoice_id: invoiceId },
    include: { invoice: { include: { member: true } } },
  });
  if (!receipt) throw notFound('member.receiptNotFound');

  const isOwner = viewer.memberId !== null && viewer.memberId === receipt.member_id;
  if (!isOwner && !viewer.isAdmin) throw notFound('member.receiptNotFound');

  if (receipt.pdf_path && (await storage.current.exists(receipt.pdf_path))) {
    return {
      stream: await storage.current.getStream(receipt.pdf_path),
      filename: `${receipt.receipt_number}.pdf`,
    };
  }

  const buffer = await renderReceiptPdf({
    org: await orgInfo(),
    member: {
      company_name: receipt.invoice.member.company_name,
      legal_name: receipt.invoice.member.legal_name,
      gst_number: receipt.invoice.member.gst_number,
      address: null,
    },
    invoice: {
      invoice_number: receipt.invoice.invoice_number,
      currency: receipt.invoice.currency,
    },
    receipt: {
      receipt_number: receipt.receipt_number,
      amount: receipt.amount.toFixed(2),
      paid_at: receipt.paid_at,
    },
  });

  const key = buildStorageKey(['receipts', String(receipt.id)], `${receipt.receipt_number}.pdf`);
  await storage.current.put(key, buffer, { mime: 'application/pdf', size: buffer.byteLength });
  await prisma.receipt.update({ where: { id: receipt.id }, data: { pdf_path: key } });

  await writeAudit(prisma, {
    ...memberAudit({ id: viewer.memberId ?? 0n, ip: null, userAgent: null, requestId: null }),
    action: AUDIT_ACTIONS.RECEIPT_ISSUED,
    entityName: 'Receipts',
    entityId: receipt.id,
    after: { receipt_number: receipt.receipt_number },
  });

  return { stream: await storage.current.getStream(key), filename: `${receipt.receipt_number}.pdf` };
};
```

*(Check `backend/src/modules/settings/settings.service.ts` for the exact exported name of the "read all settings as a key→value map" function before writing this step — `getPublicSettings` above is a placeholder name for whichever function already returns that shape; if none does, add a thin `getSettingsMap()` there that reads all `SystemSettings` rows into a `Record<string, string>`, mirroring how `SystemSettings.tsx` already consumes them on the admin side.)*

- [ ] **Step 2: Add the controller handlers**

In `backend/src/modules/member/member.controller.ts`, add:

```typescript
const streamPdf = (res: Response, file: { stream: NodeJS.ReadableStream; filename: string }) => {
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${file.filename.replace(/["\r\n]/g, '')}"`);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Cache-Control', 'private, no-store');
  file.stream.pipe(res);
};

export const downloadInvoicePdf = handler(async (req, res) => {
  const isAdmin = req.actor?.type === 'ADMIN';
  const memberId = isAdmin ? null : (await ownMember(req)).id;
  const file = await service.getInvoicePdf(BigInt(req.params.invoiceId as string), { memberId, isAdmin });
  streamPdf(res, file);
});

export const downloadReceiptPdf = handler(async (req, res) => {
  const isAdmin = req.actor?.type === 'ADMIN';
  const memberId = isAdmin ? null : (await ownMember(req)).id;
  const file = await service.getReceiptPdf(BigInt(req.params.invoiceId as string), { memberId, isAdmin });
  streamPdf(res, file);
});
```

- [ ] **Step 3: Add the shared router**

In `backend/src/modules/member/member.routes.ts`, mirroring `documentRouter` (lines 96-144), add after it:

```typescript
/** `/api/v1/invoices` — invoice and receipt PDFs, both audiences (M5). */
export const invoiceRouter = Router();

invoiceRouter.get(
  '/:invoiceId/pdf',
  authenticateEitherAudience,
  validateRequest({ params: ownInvoicePaymentParamsSchema }),
  controller.downloadInvoicePdf,
);

invoiceRouter.get(
  '/:invoiceId/receipt/pdf',
  authenticateEitherAudience,
  validateRequest({ params: ownInvoicePaymentParamsSchema }),
  controller.downloadReceiptPdf,
);
```

(`ownInvoicePaymentParamsSchema` only checks the shape of `invoiceId`, which is why it is reused here rather than adding a third near-identical schema.)

- [ ] **Step 4: Mount it**

In `backend/src/routes/index.ts`, add `invoiceRouter` to the import from `@modules/member/member.routes` (line 12) and mount it next to `documentRouter` (near line 43):

```typescript
router.use(`${END_POINTS.V1}${END_POINTS.INVOICES}`, invoiceRouter);
```

- [ ] **Step 5: Manual verification**

Run: `cd backend && npm run build` (catches any TS error the steps above introduced)
Then start the backend and, as a signed-in member with a paid invoice, `curl` (or open in a browser while signed in via the app, since this needs a real bearer token) `GET /api/v1/invoices/:id/pdf` — expect a `%PDF-` response with `Content-Type: application/pdf`. Repeat for `/receipt/pdf` on the same invoice after paying it.

- [ ] **Step 6: Commit**

```bash
git add backend/src/modules/member backend/src/routes/index.ts
git commit -m "feat(invoice): serve invoice and receipt PDFs to both audiences"
```

---

### Task 5: Customer — types, endpoints, service

**Files:**
- Modify: `customer/src/types/member.ts`
- Modify: `customer/src/constants/endpoints.ts`
- Modify: `customer/src/services/MemberService.ts`

**Interfaces:**
- Produces: `MemberInvoice` type, `MemberProfile.invoices`, `MemberService.payInvoice(invoiceId): Promise<void>`, `MemberService.invoicePdfUrl(invoiceId)`, `MemberService.receiptPdfUrl(invoiceId)` — task 7 and 8 both depend on these.

- [ ] **Step 1: Add the invoice type and extend `MemberProfile`**

In `customer/src/types/member.ts`, add near the other domain types (before `export interface MemberProfile`, around line 118):

```typescript
export type InvoiceStatus = 'DRAFT' | 'ISSUED' | 'PARTIALLY_PAID' | 'PAID' | 'OVERDUE' | 'CANCELLED';

export interface MemberInvoice {
  id: string;
  invoice_number: string;
  status: InvoiceStatus;
  issue_date: string | null;
  due_date: string | null;
  total_amount: string;
  amount_paid: string;
  balance_due: string;
  currency: string;
}
```

Then add `invoices: MemberInvoice[];` to `MemberProfile` (line 118-140), next to the existing `addresses: MemberAddress[];`.

- [ ] **Step 2: Normalise it**

In `customer/src/types/member.ts`, add a `normaliseInvoice` function near `normaliseMember` (before it, since `normaliseMember` will call it):

```typescript
function normaliseInvoice(raw: unknown): MemberInvoice {
  const source = asRecord(raw);

  return {
    id: str(source.id) ?? '',
    invoice_number: str(source.invoice_number) ?? '',
    status: (str(source.status) as InvoiceStatus) ?? 'DRAFT',
    issue_date: str(source.issue_date),
    due_date: str(source.due_date),
    total_amount: str(source.total_amount) ?? '0.00',
    amount_paid: str(source.amount_paid) ?? '0.00',
    balance_due: str(source.balance_due) ?? '0.00',
    currency: str(source.currency) ?? 'INR',
  };
}
```

In `normaliseMember`'s return object (around line 308-334), add:

```typescript
    invoices: Array.isArray(source.invoices) ? source.invoices.map(normaliseInvoice) : [],
```

- [ ] **Step 3: Add the endpoints**

In `customer/src/constants/endpoints.ts`, next to `membersMe` (line ~40), add:

```typescript
  memberInvoicePay: (invoiceId: string) => `/members/me/invoices/${invoiceId}/pay`,
  invoicePdf: (invoiceId: string) => `/invoices/${invoiceId}/pdf`,
  invoiceReceiptPdf: (invoiceId: string) => `/invoices/${invoiceId}/receipt/pdf`,
```

- [ ] **Step 4: Add the service methods**

In `customer/src/services/MemberService.ts`, add near the other C-15/profile methods:

```typescript
  /**
   * C-13/C-19. Flips the invoice to PAID and, if it was the membership
   * invoice, activates the member — the same transaction the admin's
   * "Mark as paid" already runs, just member-initiated. Callers reload the
   * profile afterwards rather than trusting this response, since the admin
   * path's response shape carries a thin member row, not the full detail.
   */
  async payInvoice(invoiceId: string): Promise<void> {
    await ApiService.post<unknown>(ENDPOINTS.memberInvoicePay(invoiceId), {});
  },

  /** Opens the invoice PDF in a new tab. Auth is cookie/header based like every other call. */
  invoicePdfUrl(invoiceId: string): string {
    return `${API_ORIGIN}${ENDPOINTS.invoicePdf(invoiceId)}`;
  },

  receiptPdfUrl(invoiceId: string): string {
    return `${API_ORIGIN}${ENDPOINTS.invoiceReceiptPdf(invoiceId)}`;
  },
```

*(Check how `ApiService`/`BaseService` attaches the bearer token — if it is an `Authorization` header set by an axios interceptor rather than a cookie, a plain `<a href>` to `invoicePdfUrl` will 401. In that case, follow `downloadDocument`'s existing pattern in this same file — `BaseService.get(..., {responseType: 'blob'})` plus the `content-disposition` filename parsing and `URL.createObjectURL` save — instead of a bare URL, and expose `downloadInvoicePdf(invoiceId)` / `downloadReceiptPdf(invoiceId)` methods instead of URL-builders. Decide by reading `customer/src/services/ApiService.ts`'s auth attachment before writing task 8.)*

- [ ] **Step 5: Typecheck**

Run: `cd customer && npx tsc --noEmit`
Expected: no new errors.

- [ ] **Step 6: Commit**

```bash
git add customer/src/types/member.ts customer/src/constants/endpoints.ts customer/src/services/MemberService.ts
git commit -m "feat(billing): customer types and service methods for invoices"
```

---

### Task 6: Backend — admin invoice list endpoint

**Files:**
- Modify: `backend/src/modules/member/member.repository.ts`
- Modify: `backend/src/modules/member/member.types.ts`
- Modify: `backend/src/modules/member/member.service.ts`
- Modify: `backend/src/modules/member/member.controller.ts`
- Modify: `backend/src/modules/member/member.routes.ts`
- Test: `backend/src/modules/member/member.invoiceList.test.ts`

**Interfaces:**
- Produces: `GET /v1/admin/invoices` (`invoice.view`), paginated, filterable by `status`/`search`, same envelope shape as `GET /v1/admin/members` — task 9's admin page depends on this.

- [ ] **Step 1: Write the failing test**

Create `backend/src/modules/member/member.invoiceList.test.ts`:

```typescript
import { describe, expect, it, vi } from 'vitest';

const queryRaw = vi.fn();

vi.mock('@db/prisma', () => ({ prisma: { $queryRaw: (...a: unknown[]) => queryRaw(...a) } }));

const { listInvoicesAdmin } = await import('@modules/member/member.service');

describe('listInvoicesAdmin', () => {
  it('returns rows and reads total off the windowed count', async () => {
    queryRaw.mockResolvedValue([
      { id: 1n, invoice_number: 'IN202603001', status: 'PAID', total: 3n },
      { id: 2n, invoice_number: 'IN202603002', status: 'ISSUED', total: 3n },
    ]);

    const result = await listInvoicesAdmin({
      page: 1,
      limit: 20,
      sortBy: 'issue_date',
      sortOrder: 'desc',
    });

    expect(result.rows).toHaveLength(2);
    expect(result.total).toBe(3);
  });

  it('returns total 0 on an empty page rather than throwing', async () => {
    queryRaw.mockResolvedValue([]);

    const result = await listInvoicesAdmin({
      page: 1,
      limit: 20,
      sortBy: 'issue_date',
      sortOrder: 'desc',
    });

    expect(result.rows).toEqual([]);
    expect(result.total).toBe(0);
  });
});
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd backend && npx vitest run src/modules/member/member.invoiceList.test.ts`
Expected: FAIL — `listInvoicesAdmin` is not exported.

- [ ] **Step 3: Add the repository query**

In `backend/src/modules/member/member.repository.ts`, mirroring `listMembers` (lines 94-173), add:

```typescript
export interface InvoiceListRow {
  id: bigint;
  invoice_number: string;
  invoice_type: string;
  status: string;
  issue_date: Date;
  due_date: Date;
  total_amount: Prisma.Decimal;
  amount_paid: Prisma.Decimal;
  balance_due: Prisma.Decimal;
  currency: string;
  member_id: bigint;
  company_name: string;
  member_code: string | null;
  total: bigint;
}

export const listInvoices = (
  db: Db,
  params: {
    search?: string | undefined;
    statuses?: string[] | undefined;
    sortBy: string;
    sortOrder: 'asc' | 'desc';
    limit: number;
    offset: number;
  },
): Promise<InvoiceListRow[]> => {
  const search = params.search ? `%${params.search}%` : null;
  const statuses = params.statuses?.length ? params.statuses : null;
  const sortColumn = Prisma.raw(`i."${params.sortBy}"`);
  const sortDirection = Prisma.raw(params.sortOrder === 'asc' ? 'ASC' : 'DESC');

  return db.$queryRaw<InvoiceListRow[]>`
    SELECT i.id,
           i.invoice_number,
           i.invoice_type,
           i.status,
           i.issue_date,
           i.due_date,
           i.total_amount,
           i.amount_paid,
           i.balance_due,
           i.currency,
           m.id AS member_id,
           m.company_name,
           m.member_code,
           count(*) OVER () AS total
      FROM "Invoices" i
      JOIN "Members" m ON m.id = i.member_id
     WHERE i."deletedAt" IS NULL
       AND (${statuses}::text[] IS NULL OR i.status::text = ANY(${statuses}::text[]))
       AND (${search}::text IS NULL
            OR i.invoice_number ILIKE ${search}
            OR m.company_name ILIKE ${search}
            OR m.member_code ILIKE ${search})
     ORDER BY ${sortColumn} ${sortDirection}, i.id DESC
     LIMIT ${params.limit} OFFSET ${params.offset}`;
};
```

- [ ] **Step 4: Add the zod schema**

In `backend/src/modules/member/member.types.ts`, next to `listMembersSchema`, add:

```typescript
export const INVOICE_STATUSES = ['DRAFT', 'ISSUED', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CANCELLED'] as const;
export const INVOICE_SORT_COLUMNS = ['issue_date', 'due_date', 'total_amount', 'invoice_number'] as const;

export const listInvoicesSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).default(20).transform((v) => Math.min(v, 100)),
  search: trimmed(150).min(1).optional(),
  status: csv(z.enum(INVOICE_STATUSES)),
  sortBy: z.enum(INVOICE_SORT_COLUMNS).default('issue_date'),
  sortOrder: z.enum(['asc', 'desc']).default('desc'),
});

export type ListInvoicesQuery = z.infer<typeof listInvoicesSchema>;
```

*(`trimmed` is already defined/imported at the top of this file, used by `listMembersSchema`'s `search` field — reuse it as-is.)*

- [ ] **Step 5: Add the service function**

In `backend/src/modules/member/member.service.ts`, next to `listMembers` (line 445), add:

```typescript
export const listInvoicesAdmin = async (query: ListInvoicesQuery) => {
  const rows = await repo.listInvoices(prisma, {
    search: query.search,
    statuses: query.status,
    sortBy: query.sortBy,
    sortOrder: query.sortOrder,
    limit: query.limit,
    offset: (query.page - 1) * query.limit,
  });

  return { rows, total: rows.length > 0 ? Number(rows[0]!.total) : 0 };
};
```

- [ ] **Step 6: Add the controller handler**

In `backend/src/modules/member/member.controller.ts`, next to `listMembers` (line 296), add:

```typescript
export const listInvoicesAdmin = handler(async (req, res) => {
  const query = req.query as unknown as Parameters<typeof service.listInvoicesAdmin>[0];
  const result = await service.listInvoicesAdmin(query);

  handleApiResponse(res, {
    responseType: RES_STATUS.GET,
    data: serialise(result.rows),
    pagination: { page: query.page, limit: query.limit, total: result.total },
  });
});
```

- [ ] **Step 7: Wire the route**

In `backend/src/modules/member/member.routes.ts`, import `listInvoicesSchema` from `member.types`, then add to `memberAdminRouter` (near the existing `GET /members` route, line 151-156):

```typescript
memberAdminRouter.get(
  END_POINTS.INVOICES,
  authorize('invoice.view'),
  validateRequest({ query: listInvoicesSchema }),
  controller.listInvoicesAdmin,
);
```

- [ ] **Step 8: Run the tests**

Run: `cd backend && npx vitest run src/modules/member/member.invoiceList.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 9: Full suite + commit**

Run: `cd backend && npm test`

```bash
git add backend/src/modules/member
git commit -m "feat(invoice): admin-wide invoice list, GET /admin/invoices"
```

---

### Task 7: Customer — wire the "Pay to activate" button

**Files:**
- Modify: `customer/src/components/application/ApplicationView.tsx:62,179`
- Modify: `customer/src/components/application/ApplicationTracker.tsx`

**Interfaces:**
- Consumes: `MemberService.payInvoice` (task 5), `Dialog` (already imported in `ApplicationTracker.tsx`, used identically for the withdraw flow at line 335-350).

- [ ] **Step 1: Pass `reloadMember` down**

In `customer/src/components/application/ApplicationView.tsx`, change line 62:

```typescript
  const { member, loading: memberLoading, reload: reloadMember } = useMemberRecord();
```

And the `<ApplicationTracker>` call (line 173-180):

```typescript
    <ApplicationTracker
      application={picked}
      detail={detail}
      member={memberLoading ? null : member}
      catalogue={catalogue}
      onStartNew={startNewApplication}
      reload={reload}
      reloadMember={reloadMember}
    />
```

- [ ] **Step 2: Extend the props and add pay state**

In `customer/src/components/application/ApplicationTracker.tsx`, add to `ApplicationTrackerProps` (line 49-57):

```typescript
  reloadMember: () => Promise<void>;
```

Add to the component's state block (near line 68-71):

```typescript
  const [payOpen, setPayOpen] = useState(false);
  const [paying, setPaying] = useState(false);
  const [payError, setPayError] = useState<string | null>(null);
```

- [ ] **Step 3: Find the payable invoice and add the confirm handler**

Near the `fee` computation (line 90-94), add:

```typescript
  const payableInvoice = member?.invoices.find((invoice) =>
    (['ISSUED', 'PARTIALLY_PAID', 'OVERDUE'] as const).includes(
      invoice.status as 'ISSUED' | 'PARTIALLY_PAID' | 'OVERDUE',
    ),
  );

  const confirmPay = async () => {
    if (!payableInvoice) return;
    setPayError(null);
    setPaying(true);
    try {
      await MemberService.payInvoice(payableInvoice.id);
      await reloadMember();
      toast.success('Payment received', {
        description: 'Your membership is now active.',
      });
      setPayOpen(false);
    } catch (error) {
      setPayError(errorMessage(error, 'We could not record your payment. Try again.'));
    } finally {
      setPaying(false);
    }
  };
```

Add the import at the top of the file, next to `ApplicationService`:

```typescript
import MemberService from '@/services/MemberService';
```

- [ ] **Step 4: Replace the disabled button**

Replace lines 223-238 (the disabled "Pay to activate" block) with:

```tsx
          <div className="mt-6 flex flex-col gap-2 border-t border-border pt-5">
            <div>
              {payableInvoice ? (
                <Button variant="primary" size="lg" onClick={() => setPayOpen(true)}>
                  Pay to activate
                </Button>
              ) : (
                <Button
                  variant="primary"
                  size="lg"
                  disabled
                  disabledReason="Your invoice has not arrived on your account yet. Check back shortly, or look for it in your email."
                >
                  Pay to activate
                </Button>
              )}
            </div>
            <p className="text-sm text-fg-muted">
              {payableInvoice
                ? `Invoice ${payableInvoice.invoice_number}. Your membership becomes active the moment it is paid.`
                : 'Your invoice number, the exact amount and the due date were emailed to you when the association approved this.'}
            </p>
          </div>
```

- [ ] **Step 5: Add the confirm dialog**

Next to the existing withdraw `<Dialog>` (line 335-350), add:

```tsx
      <Dialog
        open={payOpen}
        onClose={() => setPayOpen(false)}
        variant="primary"
        title="Pay to activate your membership?"
        description={
          payableInvoice
            ? `This confirms payment of ${payableInvoice.currency} ${payableInvoice.total_amount} for invoice ${payableInvoice.invoice_number}. Your membership activates immediately.`
            : undefined
        }
        confirmLabel="Confirm payment"
        confirming={paying}
        onConfirm={confirmPay}
      >
        {payError ? (
          <Alert variant="danger" title="Payment was not recorded">
            {payError}
          </Alert>
        ) : null}
      </Dialog>
```

*(Check `Dialog`'s `variant` prop options in `customer/src/components/ui/Dialog.tsx` — the withdraw dialog uses `"danger"`; if there is no `"primary"` variant, use whatever the component exposes for a neutral/affirmative confirm, e.g. `"default"`.)*

- [ ] **Step 6: Typecheck**

Run: `cd customer && npx tsc --noEmit`

- [ ] **Step 7: Manual verification**

Run the customer dev server, sign in as a member whose application is `APPROVED` with an `ISSUED` invoice, open the tracker, click "Pay to activate", confirm, and verify the card updates to show the membership number and the button disappears (no more payable invoice).

- [ ] **Step 8: Commit**

```bash
git add customer/src/components/application
git commit -m "feat(billing): wire the Pay to activate button to the self-service pay endpoint"
```

---

### Task 8: Customer — real Billing/Invoices page

**Files:**
- Create: `customer/src/components/billing/InvoiceList.tsx`
- Modify: `customer/src/app/(member)/invoices/page.tsx`

**Interfaces:**
- Consumes: `useMemberRecordSource` (`@/components/member/useMemberRecord`), `MemberService.payInvoice`/`invoicePdfUrl`/`receiptPdfUrl` (task 5), `StatusChip` with `domain="invoice"` (already mapped in `customer/src/components/ui/statusMap.ts:105`).

- [ ] **Step 1: Write `InvoiceList.tsx`**

Create `customer/src/components/billing/InvoiceList.tsx`:

```tsx
'use client';

import { useState } from 'react';

import Alert from '@/components/ui/Alert';
import Button from '@/components/ui/Button';
import Card from '@/components/ui/Card';
import Dialog from '@/components/ui/Dialog';
import ErrorState from '@/components/ui/ErrorState';
import MoneyText from '@/components/ui/MoneyText';
import Skeleton from '@/components/ui/Skeleton';
import StatusChip from '@/components/ui/StatusChip';
import { errorMessage, requestIdOf } from '@/components/member/memberErrors';
import { useMemberRecordSource } from '@/components/member/useMemberRecord';
import MemberService from '@/services/MemberService';
import type { MemberInvoice } from '@/types/member';
import { formatDate } from '@/utils/format';

/**
 * C-19 — every invoice a member has ever had, oldest fields last: `GET
 * /members/me` already returns them (`findMemberDetail`, `issue_date desc`),
 * so this screen reads the same profile load the rest of the portal uses
 * rather than a second endpoint.
 */

const PAYABLE_STATUSES = new Set(['ISSUED', 'PARTIALLY_PAID', 'OVERDUE']);

export default function InvoiceList() {
  const { member, loading, error, reload } = useMemberRecordSource();
  const [target, setTarget] = useState<MemberInvoice | null>(null);
  const [paying, setPaying] = useState(false);
  const [payError, setPayError] = useState<string | null>(null);

  if (loading && !member) {
    return <Skeleton variant="list" />;
  }

  if (error || !member) {
    return (
      <ErrorState
        title="We could not load your invoices"
        description="Try again, and if it keeps happening, quote the reference below."
        onRetry={() => void reload()}
        requestId={requestIdOf(error)}
      />
    );
  }

  const confirmPay = async () => {
    if (!target) return;
    setPayError(null);
    setPaying(true);
    try {
      await MemberService.payInvoice(target.id);
      await reload();
      setTarget(null);
    } catch (caught) {
      setPayError(errorMessage(caught, 'We could not record your payment. Try again.'));
    } finally {
      setPaying(false);
    }
  };

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-semibold tracking-[-0.01em] text-fg md:text-3xl">Billing</h1>

      {member.invoices.length === 0 ? (
        <Card title="No invoices yet">
          <p className="text-sm text-fg-muted">
            An invoice appears here as soon as the association raises one for you.
          </p>
        </Card>
      ) : (
        <div className="flex flex-col gap-3">
          {member.invoices.map((invoice) => (
            <Card key={invoice.id}>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex flex-col gap-[2px]">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-mono text-sm text-fg">{invoice.invoice_number}</span>
                    <StatusChip domain="invoice" status={invoice.status} />
                  </div>
                  <span className="text-xs text-fg-muted">
                    Due {invoice.due_date ? formatDate(invoice.due_date) : '—'}
                  </span>
                </div>

                <div className="flex items-center gap-3">
                  <MoneyText amount={invoice.total_amount} currency={invoice.currency} />

                  <a
                    href={MemberService.invoicePdfUrl(invoice.id)}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm text-fg-muted underline"
                  >
                    Invoice PDF
                  </a>

                  {invoice.status === 'PAID' ? (
                    <a
                      href={MemberService.receiptPdfUrl(invoice.id)}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-sm text-fg-muted underline"
                    >
                      Receipt
                    </a>
                  ) : null}

                  {PAYABLE_STATUSES.has(invoice.status) ? (
                    <Button onClick={() => setTarget(invoice)}>Pay</Button>
                  ) : null}
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}

      <Dialog
        open={target !== null}
        onClose={() => setTarget(null)}
        title="Pay this invoice?"
        description={
          target ? `This confirms payment of ${target.currency} ${target.total_amount} for invoice ${target.invoice_number}.` : undefined
        }
        confirmLabel="Confirm payment"
        confirming={paying}
        onConfirm={confirmPay}
      >
        {payError ? (
          <Alert variant="danger" title="Payment was not recorded">
            {payError}
          </Alert>
        ) : null}
      </Dialog>
    </div>
  );
}
```

*(Check `errorMessage`/`requestIdOf`'s actual export location — `ApplicationTracker.tsx` imports `errorMessage` from `@/components/member/memberErrors`; confirm `requestIdOf` lives there too, as `ApplicationView.tsx` uses it. Check `Skeleton`'s `variant` prop accepts `"list"` — `ApplicationTracker`/`ApplicationView` only use `"detail"`; if `"list"` is not a real variant, use `"detail"`.)*

- [ ] **Step 2: Replace the placeholder page**

Replace the full contents of `customer/src/app/(member)/invoices/page.tsx`:

```tsx
import type { Metadata } from 'next';

import InvoiceList from '@/components/billing/InvoiceList';

export const metadata: Metadata = { title: 'Billing' };

export default function InvoicesPage() {
  return <InvoiceList />;
}
```

- [ ] **Step 3: Typecheck**

Run: `cd customer && npx tsc --noEmit`

- [ ] **Step 4: Manual verification**

Run the customer dev server, sign in as a member with at least one paid and one unpaid invoice, open Billing, confirm: both rows show with correct status chips, "Pay" only appears on the unpaid one, "Invoice PDF" opens a real PDF for both, "Receipt" only appears on the paid one and opens a real PDF, and paying the unpaid one updates the row in place without a page reload.

- [ ] **Step 5: Commit**

```bash
git add customer/src/components/billing customer/src/app/\(member\)/invoices/page.tsx
git commit -m "feat(billing): real customer invoice list, replacing the M5 placeholder"
```

---

### Task 9: Admin — real Money → Invoices page

**Files:**
- Create: `admin/src/services/invoicesService.ts`
- Create: `admin/src/pages/billing/Invoices.tsx`
- Modify: `admin/src/routes/AppRoutes.tsx`
- Modify: `admin/src/constant/navigation.tsx:161`

**Interfaces:**
- Consumes: `GET /admin/invoices` (task 6), `DataTable`/`SearchInput`/`FilterDropdown`/`StatusChip`/`MoneyText`/`DateCell` (`.claude/skills/association-admin-ui/`, used exactly this way in `ApplicationQueue.tsx`).

- [ ] **Step 1: Fix the nav module label**

In `admin/src/constant/navigation.tsx`, line 161, change:

```typescript
        module: 'M4',
```

to:

```typescript
        module: 'M5',
```

(This item was mislabeled — the per-member invoice card shipped in M4, but this global list is genuinely M5 work, same cycle as "Payments" directly below it.)

- [ ] **Step 2: Write `invoicesService.ts`**

Create `admin/src/services/invoicesService.ts`:

```typescript
import { ENDPOINTS } from '@/constant/endpoints';
import { BaseService, type ApiResult } from '@/services/BaseService';

export type InvoiceStatus = 'DRAFT' | 'ISSUED' | 'PARTIALLY_PAID' | 'PAID' | 'OVERDUE' | 'CANCELLED';
export type InvoiceSortBy = 'issue_date' | 'due_date' | 'total_amount' | 'invoice_number';

export interface InvoiceListRow {
  id: string;
  invoice_number: string;
  invoice_type: string;
  status: InvoiceStatus;
  issue_date: string;
  due_date: string;
  total_amount: string;
  amount_paid: string;
  balance_due: string;
  currency: string;
  member_id: string;
  company_name: string;
  member_code: string | null;
}

export interface ListInvoicesParams {
  page?: number;
  limit?: number;
  search?: string;
  status?: string;
  sortBy?: InvoiceSortBy;
  sortOrder?: 'asc' | 'desc';
}

const query = (params?: ListInvoicesParams): string => {
  if (!params) return '';
  const entries = Object.entries(params).filter(([, v]) => v !== undefined && v !== '');
  if (!entries.length) return '';
  return `?${new URLSearchParams(entries as [string, string][]).toString()}`;
};

const InvoicesService = {
  list: (params?: ListInvoicesParams): Promise<ApiResult<InvoiceListRow[]>> =>
    BaseService.get(`${ENDPOINTS.INVOICES.LIST}${query(params)}`),

  pdfUrl: (id: string): string => `${ENDPOINTS.INVOICES.pdf(id)}`,
  receiptPdfUrl: (id: string): string => `${ENDPOINTS.INVOICES.receiptPdf(id)}`,
};

export default InvoicesService;
```

*(Add `INVOICES: { LIST: '/admin/invoices', pdf: (id: string) => \`/invoices/${id}/pdf\`, receiptPdf: (id: string) => \`/invoices/${id}/receipt/pdf\` }` to `admin/src/constant/endpoints.ts`, next to the existing `MEMBERS` block — check that file's exact base-URL prefixing convention first, since `MEMBERS.markInvoicePaid` already builds a full `/admin/members/...` path and the PDF routes are NOT under `/admin`, they are shared — mirror `ENDPOINTS.DOCUMENTS`'s pattern if one already crosses that boundary, otherwise hardcode the `/invoices/...` prefix exactly as shown.)*

- [ ] **Step 3: Write the page**

Create `admin/src/pages/billing/Invoices.tsx`, modelled directly on `ApplicationsTab` in `ApplicationQueue.tsx` (same hooks, same `DataTable` usage, narrower filter set):

```tsx
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  Card,
  DataTable,
  DateCell,
  FilterDropdown,
  FilterGroup,
  MoneyText,
  MultiSelect,
  PageHeader,
  SearchInput,
  StackedCell,
  StatusChip,
} from '@/components/ui';
import type { TableSort } from '@/components/ui';
import InvoicesService, {
  type InvoiceListRow,
  type InvoiceSortBy,
  type InvoiceStatus,
} from '@/services/invoicesService';
import type { PaginationMeta } from '@/services/BaseService';
import { asDisplayError, type DisplayError } from '@/utils/apiError';

/**
 * A-14 — every invoice across every member, so Accounts can answer "who is
 * behind on payment" without opening one member at a time. The per-member
 * card on the profile screen (M4) stays as the place to act on a single
 * invoice; this page is purely for finding one.
 */

const STATUS_OPTIONS: Array<{ value: InvoiceStatus; label: string }> = [
  { value: 'ISSUED', label: 'Issued' },
  { value: 'PARTIALLY_PAID', label: 'Partially paid' },
  { value: 'PAID', label: 'Paid' },
  { value: 'OVERDUE', label: 'Overdue' },
  { value: 'CANCELLED', label: 'Cancelled' },
];

const DEFAULT_SORT: TableSort = { sortBy: 'issue_date', sortOrder: 'desc' };
const SORTABLE: InvoiceSortBy[] = ['issue_date', 'due_date', 'total_amount', 'invoice_number'];
const isSortable = (value: string): value is InvoiceSortBy =>
  (SORTABLE as string[]).includes(value);

export const Invoices = () => {
  const [params, setParams] = useSearchParams();
  const [rows, setRows] = useState<InvoiceListRow[]>([]);
  const [pagination, setPagination] = useState<PaginationMeta | undefined>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<DisplayError | null>(null);

  const search = params.get('q') ?? '';
  const statuses = (params.get('status') ?? '').split(',').filter(Boolean) as InvoiceStatus[];
  const page = Number(params.get('page') ?? '1') || 1;
  const sortByParam = params.get('sortBy') ?? '';
  const sort: TableSort = {
    sortBy: isSortable(sortByParam) ? sortByParam : DEFAULT_SORT.sortBy,
    sortOrder: params.get('sortOrder') === 'asc' ? 'asc' : 'desc',
  };

  const hasFilters = Boolean(search || statuses.length);

  const patchParams = useCallback(
    (patch: Record<string, string | null>, options?: { keepPage?: boolean }) => {
      setParams(
        (previous) => {
          const next = new URLSearchParams(previous);
          Object.entries(patch).forEach(([key, value]) => {
            if (value === null || value === '') next.delete(key);
            else next.set(key, value);
          });
          if (!options?.keepPage) next.delete('page');
          return next;
        },
        { replace: true },
      );
    },
    [setParams],
  );

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await InvoicesService.list({
        page,
        limit: 20,
        ...(search ? { search } : {}),
        ...(statuses.length ? { status: statuses.join(',') } : {}),
        sortBy: sort.sortBy as InvoiceSortBy,
        sortOrder: sort.sortOrder,
      });
      setRows(result.data);
      setPagination(result.pagination);
    } catch (caught) {
      setError(asDisplayError(caught));
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, search, params.get('status'), sort.sortBy, sort.sortOrder]);

  useEffect(() => {
    void load();
  }, [load]);

  const columns = useMemo(
    () => [
      {
        title: 'Invoice',
        dataIndex: 'invoice_number',
        key: 'invoice_number',
        sorter: true,
        width: 170,
        render: (value: string) => <span className="font-mono text-supporting text-fg">{value}</span>,
      },
      {
        title: 'Member',
        dataIndex: 'company_name',
        key: 'company_name',
        width: 220,
        render: (_: unknown, row: InvoiceListRow) => (
          <StackedCell primary={row.company_name} secondary={row.member_code ?? '—'} />
        ),
      },
      {
        title: 'Status',
        dataIndex: 'status',
        key: 'status',
        width: 140,
        render: (value: InvoiceStatus) => <StatusChip domain="invoice" status={value} />,
      },
      {
        title: 'Amount',
        dataIndex: 'total_amount',
        key: 'total_amount',
        sorter: true,
        width: 150,
        render: (_: unknown, row: InvoiceListRow) => (
          <MoneyText amount={row.total_amount} currency={row.currency} />
        ),
      },
      {
        title: 'Issue date',
        dataIndex: 'issue_date',
        key: 'issue_date',
        sorter: true,
        width: 130,
        render: (_: unknown, row: InvoiceListRow) => <DateCell value={row.issue_date} />,
      },
      {
        title: 'Due date',
        dataIndex: 'due_date',
        key: 'due_date',
        sorter: true,
        width: 130,
        render: (_: unknown, row: InvoiceListRow) => <DateCell value={row.due_date} />,
      },
      {
        title: 'Document',
        key: 'document',
        width: 150,
        render: (_: unknown, row: InvoiceListRow) => (
          <a
            href={InvoicesService.pdfUrl(row.id)}
            target="_blank"
            rel="noopener noreferrer"
            className="text-supporting text-fg-muted underline"
          >
            PDF
          </a>
        ),
      },
    ],
    [],
  );

  return (
    <div className="flex h-full min-h-0 flex-col">
      <PageHeader
        title="Invoices"
        actions={
          <>
            <SearchInput
              value={search}
              onChange={(next) => patchParams({ q: next.trim() || null })}
              label="Search invoices"
              placeholder="Search invoice number, company or member code"
              className="w-[320px] max-w-full"
            />
            <FilterDropdown<{ status: InvoiceStatus[] }>
              value={{ status: statuses }}
              emptyValue={{ status: [] }}
              onApply={(draft) => patchParams({ status: draft.status.join(',') || null })}
              onClear={() => patchParams({ status: null })}
              activeCount={statuses.length ? 1 : 0}
            >
              {(draft, setDraft) => (
                <FilterGroup label="Status">
                  <MultiSelect
                    value={draft.status}
                    placeholder="Any status"
                    options={STATUS_OPTIONS}
                    onChange={(next) => setDraft({ status: next as InvoiceStatus[] })}
                  />
                </FilterGroup>
              )}
            </FilterDropdown>
          </>
        }
      />

      <Card flush className="min-h-0 flex-1">
        <DataTable<InvoiceListRow>
          unit="invoices"
          serial
          rowKey="id"
          loading={loading}
          error={error}
          onRetry={() => void load()}
          pagination={pagination}
          onPageChange={(nextPage) =>
            patchParams({ page: String(nextPage) }, { keepPage: true })
          }
          sort={sort}
          onSortChange={(next) =>
            patchParams({ sortBy: next?.sortBy ?? null, sortOrder: next?.sortOrder ?? null })
          }
          dataSource={rows}
          columns={columns}
          filtered={hasFilters}
          onClearFilter={() => patchParams({ q: null, status: null })}
          emptyTitle="No invoices yet"
          emptyDescription="An invoice appears here the moment one is raised for a member."
        />
      </Card>
    </div>
  );
};

export default Invoices;
```

*(`PageHeader`'s `actions` prop name is inferred from `ApplicationQueue.tsx`'s `Tabs actions={searchBox}` usage — confirm the real prop on `PageHeader` itself, since this page has no tabs and renders search/filter directly on the header rather than via `Tabs`. Check `.claude/skills/association-admin-ui/components.md` for `PageHeader`'s actual prop for a trailing toolbar before writing this step, and adjust if it differs.)*

- [ ] **Step 4: Wire the route**

In `admin/src/routes/AppRoutes.tsx`, add `'/billing/invoices'` to the exclusion array (line 277-288, alongside `/settings/workflow`), then add a real route next to the `/settings/workflow` one (near line 255-261):

```tsx
        <Route
          path="/billing/invoices"
          element={
            <RequirePermission anyOf={['invoice.view']}>
              <Invoices />
            </RequirePermission>
          }
        />
```

Import `Invoices` at the top of the file, next to the other page imports.

- [ ] **Step 5: Typecheck + lint**

Run: `cd admin && npx tsc --noEmit && npx eslint src/pages/billing src/services/invoicesService.ts`

- [ ] **Step 6: Manual verification**

Run the admin dev server, sign in, open Money → Invoices — confirm it is a real table now (not the placeholder), search and status filter work, sorting works, pagination works, and the PDF link opens a real document for at least one row.

- [ ] **Step 7: Commit**

```bash
git add admin/src/pages/billing admin/src/services/invoicesService.ts admin/src/routes/AppRoutes.tsx admin/src/constant/navigation.tsx
git commit -m "feat(billing): real admin Money > Invoices screen, org-wide"
```

---

### Task 10: Admin — download links on the per-member invoice card

**Files:**
- Modify: `admin/src/pages/members/ProfileTab.tsx:376-399`

**Interfaces:**
- Consumes: `InvoicesService.pdfUrl`/`receiptPdfUrl` (task 9).

- [ ] **Step 1: Add the links**

In `admin/src/pages/members/ProfileTab.tsx`, inside the invoice `<li>` (around line 390-397), add PDF/receipt links next to the amount, mirroring task 8's customer version:

```tsx
                <div className="flex items-center gap-3">
                  <MoneyText amount={invoice.total_amount} currency={invoice.currency} />
                  <a
                    href={InvoicesService.pdfUrl(invoice.id)}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-13 text-fg-muted underline"
                  >
                    PDF
                  </a>
                  {invoice.status === 'PAID' ? (
                    <a
                      href={InvoicesService.receiptPdfUrl(invoice.id)}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-13 text-fg-muted underline"
                    >
                      Receipt
                    </a>
                  ) : null}
                  {canRecordPayment &&
                  (invoice.status === 'ISSUED' ||
                    invoice.status === 'PARTIALLY_PAID' ||
                    invoice.status === 'OVERDUE') ? (
                    <Button onClick={() => payment.ask(invoice)}>Mark as paid</Button>
                  ) : null}
                </div>
```

Add the import: `import InvoicesService from '@/services/invoicesService';`

- [ ] **Step 2: Typecheck**

Run: `cd admin && npx tsc --noEmit`

- [ ] **Step 3: Manual verification**

Open a member with a paid and an unpaid invoice; confirm "PDF" appears on both, "Receipt" only on the paid one, both open real documents.

- [ ] **Step 4: Commit**

```bash
git add admin/src/pages/members/ProfileTab.tsx
git commit -m "feat(billing): invoice/receipt PDF links on the member profile card"
```

---

## Self-Review

**Spec coverage:**
- "Pay button works, no gateway" → Task 3 (backend), Task 7 (frontend). ✔
- "Customer sees invoice list" → Task 5 (data), Task 8 (screen). ✔
- "Admin sees every invoice" → Task 6 (data), Task 9 (screen). ✔
- "Real invoice + receipt PDF, production grade, GST-correct" → Task 1 (Receipts table), Task 2 (templates using both GSTINs + line items), Task 4 (secure download), links surfaced in Task 8 (customer), Task 9 and 10 (admin). ✔
- Existing admin "Mark as paid" path stays working and unchanged in behaviour → asserted explicitly in Task 3's test suite (`recordInvoicePayment (admin path, unchanged behaviour)`). ✔

**Open items carried forward, not silently assumed:**
- Task 5's `payInvoice`/PDF URL approach depends on how `ApiService` attaches auth — flagged inline for the implementer to check before writing the download call.
- Task 4's `orgInfo()` depends on the exact function name in `settings.service.ts` that returns all `SystemSettings` as a map — flagged inline.
- Task 9's `PageHeader` toolbar prop name is inferred, not confirmed against the component's actual source — flagged inline, with a pointer to `components.md`.
- Task 9's admin `ENDPOINTS.INVOICES` path prefix (whether PDF routes cross the `/admin` boundary) is flagged inline for the implementer to resolve against the real `endpoints.ts` conventions.

These four are marked rather than guessed at, per this project's rule against inventing behaviour that isn't already established somewhere in the code — each is a five-minute read, not a design decision.
