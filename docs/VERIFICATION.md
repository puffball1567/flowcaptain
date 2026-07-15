# Verification

This file records release-candidate verification commands and the latest known
memory-check result for FlowCaptain.

## Commands

Run these from the repository root:

```bash
nimble test -y
nimble examples -y
nimble eventReportExample -y
php adapters/laravel/tests/run.php
nimble leak -y
```

## Latest Memory Check

Date: 2026-07-15

Command:

```bash
nimble leak -y
```

Build mode:

- Nim memory manager: ARC
- Nim options: `-d:release`
- Probe binary: `/tmp/flowcaptain-leak-probe`
- Tool: Valgrind 3.18.1 Memcheck

Result:

```text
HEAP SUMMARY:
    in use at exit: 0 bytes in 0 blocks
    total heap usage: 0 allocs, 0 frees, 0 bytes allocated

All heap blocks were freed -- no leaks are possible

ERROR SUMMARY: 0 errors from 0 contexts
```

The probe is intentionally small and release-built. It is a regression guard for
definite and indirect leaks in the core plan/report lifecycle, not a substitute
for workload-specific memory profiling.
