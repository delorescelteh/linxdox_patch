# linxdox_patch — Operator Docs

Target device release:
- **Linxdot 2.0.0.05-OPEN A01 r17782-d6ec4dd717**

This repo is intended to be maintained long-term and published to GitHub as a **PRIVATE** repository.

## What lives here
1) AI operator + human co-work documentation
2) Issue tracking (local, file-based) with patch decisions and verification steps
3) Patch version control + release packaging notes

## Operating rules
- Prefer small, reversible patches.
- Every patch must have:
  - scope
  - steps
  - rollback plan
  - verification checklist
- Never assume customer has Internet.

