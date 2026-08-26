# Risks

| ID | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| R-1 | "One-week MVP" vs 21 modules | Rushed, unsafe code | High | Module-by-module cycle with an approval gate; MVP target is explicitly subordinate to correctness per master instructions §2 |
| R-2 | Unanswered OQs (gateway, fees, approval stages) stall coding | Blocked agents | High | Provider/interface abstractions (A-5, A-6) let modules ship behind an adapter; OQ owners listed per module plan |
| R-3 | Two coding agents editing the same Prisma schema/migration | Broken migration history, merge conflicts | High | Single migration owner per module cycle, named in the module plan; schema changes land before dependent work starts |
| R-4 | Encryption layer breaks debuggability and third-party tooling | Slow triage | Medium | `decrypted_data` echoed in `local` env only; Sentinel decrypts; never in staging/production |
| R-5 | AES-256-CBC with a static IV from env (Elvee scheme) is weaker than per-message IV | Ciphertext pattern leakage | Medium | Accepted for Elvee parity (ADR-004). Compensating controls: HTTPS mandatory, JWT auth, no secrets in payloads. Revisit post-MVP with per-request IV |
| R-5b | Payload encryption is **not** authentication — it obfuscates, it does not authorise | Misplaced trust | Medium | Documented in `api-conventions.md`; every endpoint still runs authn + authz + zod validation after decryption |
| R-6 | Approval workflow modelled too loosely → invalid state transitions | Corrupt membership state | Medium | Explicit transition table + DB check constraints + service-level guard, all changes inside a transaction |
| R-7 | Payment/webhook double-processing | Double credit, wrong invoice status | Medium | Unique idempotency key on `PaymentWebhookEvents`, transactional invoice update, replay-safe handler |
| R-8 | N+1 on directory/member/invoice lists | Slow admin portal | Medium | Raw SQL for list endpoints, mandatory pagination, index plan in `database-indexes.md`, Sentinel perf assertion |
| R-9 | Document endpoints leak private KYC files | Data breach | Low/High impact | No public static serving of KYC dirs; signed, expiring, authorised download endpoint only |
| R-10 | Scope creep into accounting integration | Wasted effort, contract dispute | Low | PARKED in three places; agents instructed to refuse |
| R-11 | Sentinel still configured for the Elvee stack | False green self-tests | High (today) | M0 task: rewire `sarvadhi-sentinel/config.js`, `.env.example`, package name to this platform before any module is tested |
| R-12 | proposal.pdf not machine-readable → a requirement may be missed | Missing feature late | Medium | Flagged in `requirements.md`; user to confirm coverage before M1 |
| R-13 | **Project not under version control** — two agents editing one tree with no history, branches or diffs. **User decision 2026-08-12: git deferred.** | Lost work, unresolvable conflicts, no rollback of a bad edit | High | **Accepted risk.** Compensating controls agreed: (a) agents never edit the same file in a cycle (ownership table), (b) a timestamped `tar.gz` snapshot of the repo is taken at the start and end of every cycle into a non-project directory, (c) shared core frozen after M0. Re-raise before the first deploy — `prisma/migrations` history without git is genuinely dangerous |
| R-14 | **No backup/DR policy existed** — KYC documents and financial records are unrecoverable by re-entry | Total data loss | Medium/Critical | `backup-recovery.md`: nightly dump + uploads archive, off-host copy, rehearsed restore before go-live |
| R-15 | Silent failure of jobs, backups or notifications | Members never told; reminders never sent; backups absent when needed | High | `observability.md` §6 alert table; `JobRuns` + outbox status surfaced on the admin dashboard |
| R-16 | Webhook raw body not captured → signature verification impossible | Payment fraud, or a late refactor of frozen shared core | Medium | ADR-018: `express.json({verify})` in M0 |
| R-17 | Encryption keys ship in the client bundle (`NEXT_PUBLIC_*`) and are mistaken for a security boundary | False sense of protection; secrets placed in the wrong tier | Medium | `security.md` §4 states it plainly; HTTPS mandatory; no real secret ever gets a `NEXT_PUBLIC_` name |
| R-18 | `express-rate-limit` in-memory store resets on restart and breaks across instances | Throttles bypassable | Low (single instance) | Documented OQ-14; move to Postgres/Redis before scaling |
| R-19 | Uploads grow unbounded on a single volume | Disk exhaustion takes the API down | Medium | Size caps per document type, 85 % disk alert, OQ-19 quota decision |
| R-20 | Port collision — skeleton defaults to 3000, the customer app also wants 3000 | Confusing local failures | High (today) | `versions.md` fixes ports; M0 changes the backend default to 4000 |
| R-21 | One-week MVP expectation vs an 11-cycle plan | Trust damage when the date slips | High | `planning-review.md` §7 gives an honest estimate and a "what fits in a week" subset |
| R-22 | **Accounting integration is in the signed proposal but parked for MVP** | Client judges delivery incomplete against the contract | High | Written change note under the proposal's Change Requests clause before go-live (PV-4) |
| R-23 | 3-month warranty + 8-working-hour first response (NFR-3/4) with no defect intake path or handover docs | Support obligations unmet | Medium | `deployment.md` §10 handover pack + defect intake; Sentinel reports are the regression evidence |
| R-24 | Platform runs on the **client's own hosting account** (NFR-1) whose spec, access and backup discipline we do not control | Deploy blocked; backups not actually taken | Medium | Host spec + access + backup ownership agreed before staging (OQ-10/OQ-11 now client-owned) |
| R-25 | Full project (not a one-week MVP) confirmed by the user, but client-input delays are the real schedule driver (NFR-6) | Slipped dates blamed on delivery | Medium | Each cycle's blocking open questions listed up front; sign-off dates recorded in `implementation-status.md` |

