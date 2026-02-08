# Co-work Protocol (AI operator + Human)

## Principles
- Only-True: verify facts before concluding.
- Minimize customer risk: default to read-only diagnostics; destructive changes require explicit approval.
- Capture evidence: commands run + outputs (redact secrets).

## Standard flow
1) Identify target device version and environment constraints (Internet? RTC? NTP?)
2) Collect diagnostics (logs, df, services, configs)
3) **Audit-only first** when possible (generate report; no device changes)
4) Propose patch options + tradeoffs
5) Apply patch (prefer automation)
6) Verify + record
   - Update `/etc/linxdot_patch_version`
   - Append `/etc/linxdot_patch_manifest.json`
   - Store the operator-side report artifact under `releases/` or attach to the Issue record

