# Changelog

## 0.2.0

### Added

- Added a public integration API layer that lets adapters, CLIs, and future
  bindings call FlowCaptain as the bridge to plan validation, dependency
  batches, toolkit execution, adapter-event import, health, metrics, reports,
  report rotation, diagrams, plan diff, and variant comparison.
- Added a FlowBrigade policy bridge for validating control plans and exposing
  consuming or inspecting policy decisions without reimplementing policy logic.
- Added adapter contract validation for framework adapters, including event
  type, required id, terminal status, non-negative value, and sensitive tag-key
  checks.
- Added run history snapshots and JSONL import/export so callers can store
  daily or monthly FlowCaptain results outside the library.
- Added local JSONL file and SQLite history stores for practical recurring-run
  retention without requiring an external service.
- Added history trend analysis for critical path, total work, wait, retry,
  failure, health, throughput, cycle-time, and yield signals.
- Added `docs/VERIFICATION.md` with the latest test and Valgrind ARC leak-probe
  result.

## 0.1.1

### Changed

- Switched the repository default memory manager to Nim ARC.
- Added ARC memory-model coverage for core plan/report lifecycles.
- Added `nimble leak`, a Valgrind-backed release probe that fails on definite
  or indirect leaks.

## 0.1.0

Initial FlowCaptain release candidate.

### Added

- FlowCaptain plan, node, edge, run, analysis, report, and artifact types.
- Validation, dry-run planning, simulated execution, and critical-path analysis.
- FlowDependency integration for dependency-ready batches.
- FlowWorkRunner integration through `executeWithToolkit`.
- FlowSurveyor integration for wait insights, parallelism opportunities,
  failure/retry impact, and recommendations.
- FlowLogbook, FlowGarage, and FlowBrigade Toolkit conversion helpers.
- Markdown and browser-readable HTML reports.
- Mermaid flow, structure, and comparison diagrams as secondary artifacts.
- Report rotation with latest and run-specific snapshots.
- Metric event export for downstream time-series processing.
- Adapter event JSONL support for framework and web-batch instrumentation.
- `flowcaptain_event_report` CLI for `plan.json + events.jsonl -> reports`.
- Example `billing` adapter-event plan and JSONL input.
- Thin Laravel-compatible adapter under `adapters/laravel`.
- Laravel adapter smoke test and report-generation example.
- Benchmarks for large basic Captain plans.

### Security And Privacy

- Adapter events are designed to avoid return-value and payload capture.
- Adapter JSONL parsing enforces schema, line-size, event-count, duration, and
  retry-count checks.
- Laravel adapter sanitizes ids, tags, and messages before writing JSONL.

### Notes

- The Laravel adapter is intentionally thin and framework-compatible. It does
  not require Laravel at runtime for the smoke test, but is designed to be used
  from Artisan commands, queue jobs, schedulers, and batch segments.
- Planned framework adapter order is Laravel, Symfony, Express, NestJS,
  Fastify, Prologue, FastAPI, and Spring Boot.
