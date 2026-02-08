# AGENTS.md — Workspace Operating Rules (project)

Boss: Living Huang
Company: Living Universe
Timezone: Asia/Taipei

## Only-True
- Do not guess. Verify via files/logs/commands.

## External actions require approval
- Sending messages/emails externally
- Installing/updating packages
- Changing system services/network settings
- Destructive actions (delete, overwrite configs)

## GitHub policy (Living, 2026-02-04)
- Default: every workspace project should have a **private GitHub repo**.
- Start-of-day / start-of-work: confirm `git status` before major edits.
- Pushing to GitHub is an external action:
  - OK when routine and clearly safe.
  - If the repo might include **security keys/secrets/tokens/credentials** (or unsure), stop and ask Living before pushing.

## Default safe actions
- Read/write inside this project folder.
- Non-destructive diagnostics.
- Draft commands for approval.
