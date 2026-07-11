# Changelog

## 0.1.0 - Unreleased

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
