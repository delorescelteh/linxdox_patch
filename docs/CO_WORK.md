# Co-work Protocol (AI operator + Human)

## Principles
- Only-True: verify facts before concluding.
- Minimize customer risk: default to read-only diagnostics; destructive changes require explicit approval.
- Capture evidence: commands run + outputs (redact secrets).

## Standard flow
1) Identify target device version and environment constraints (Internet? RTC? NTP?)
2) Collect diagnostics (logs, df, services, configs)
3) Propose patch options + tradeoffs
4) Apply patch (prefer automation)
5) Verify + record

