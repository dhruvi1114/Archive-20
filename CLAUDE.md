# Association Platform

This is a greenfield project.

## Stack

Customer:
Next.js + TypeScript

Admin:
React + TypeScript

Backend:
Node.js + Express + TypeScript

ORM:
Prisma

Database:
PostgreSQL

## Architecture

Customer and Admin are separate frontend applications.

Both applications communicate with the same backend API.

Business logic belongs in the backend.

## Development Process

Development happens in this order:

1. Planning
2. Coding
3. Self-Test

Two coding sub-agents will work during the coding phase.

Use the existing Self-Test Agent.
Do not create another testing agent.

## UX

Before building or changing any admin screen, use the `association-admin-ui`
skill (`.claude/skills/association-admin-ui/`). It is the catalogue of shared
components every screen is assembled from — table, search, selects, drawer,
confirm, cells, tokens — and the reason a new page looks like the existing ones.

Use first-principles design.

Every important workflow should clearly communicate:

Current State
→ Required Action
→ Next Step
→ Expected Result

Customer UX and Admin UX must be designed separately.

## Database

Use Prisma migrations.

Do not use production schema auto-sync.

Do not modify already-applied migrations.

Use proper:

- Foreign keys
- Constraints
- Indexes
- Transactions

## Scope

Accounting integration is parked.

Do not implement accounting integrations unless explicitly requested.

## Rules

Do not invent business requirements.

If something is unclear, document the ambiguity and ask for clarification.
