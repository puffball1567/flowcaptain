# FlowCaptain

Top-level orchestration and reporting layer for the FlowBrigade Toolkit.

## Intended Role

FlowCaptain coordinates the FlowBrigade Toolkit components:

- FlowDependency for graph structure
- FlowWorkRunner for execution
- FlowBrigade for runtime control
- FlowLogbook for records
- FlowSurveyor for analysis
- FlowGarage for report bundles and package manifests

## v0.1.0 Scope

The first target scenario is `daily-report`:

- define a graph
- validate it
- dry-run the execution order with FlowDependency
- run or simulate work with FlowWorkRunner
- record events
- analyze bottlenecks and critical path
- compare at least two variants
- generate browser-readable HTML and Markdown reports
- generate Mermaid diagrams as secondary artifacts
- generate a package manifest
- import framework adapter JSONL events
- provide a thin Laravel-compatible adapter for command, queue, scheduler, and
  batch instrumentation

## Install

FlowCaptain requires Nim 2.2 or newer.

After release, install it with Nimble:

```bash
nimble install flowcaptain
```

FlowCaptain depends on the FlowBrigade Toolkit libraries. Until every toolkit
package is available from the Nimble package index, the package metadata points
unregistered toolkit dependencies at their GitHub repositories.

When working from this repository, the Nimble tasks use the local `deps/`
workspace paths:

```bash
nimble test
nimble examples
nimble eventReportExample
nimble laravelAdapterExample
```

## Toolkit Execution

FlowCaptain can execute a plan through the lower-level toolkit pieces:

```nim
import flowcaptain

var plan = initCaptainPlan("daily", "Daily")
plan.nodes.add(node("extract", "Extract", plannedMs = 10))
plan.nodes.add(node("publish", "Publish", plannedMs = 20))
plan.edges.add(edge("extract-publish", "extract", "publish"))

let outcome = plan.executeWithToolkit().complete()
```

`executeWithToolkit` uses FlowDependency for dependency-ready batches and
FlowWorkRunner for execution. For production work, pass a
`WorkExecutorRegistry` with executors for each node.

## Adapter Events

Framework adapters can start with lightweight JSON Lines events instead of
embedding FlowCaptain deeply into application code. This is intended for web
batch, job, queue, and scheduled-task instrumentation.

```json
{"schemaVersion":1,"eventType":"nodeFinished","flowId":"billing","runId":"run-1","variantId":"A","nodeId":"calculate","durationMs":850,"status":"succeeded","retryCount":1}
```

FlowCaptain can parse these events with `parseAdapterEventsJsonLines` and turn
them into an analyzable outcome with `outcomeFromAdapterEvents`.

The CLI can generate browser-readable reports from a plan JSON and adapter
event JSONL:

```bash
nimble eventReportExample
```

See [docs/ADAPTER_EVENTS.md](docs/ADAPTER_EVENTS.md) for the event format,
production notes, and adapter order.

Planned framework adapter order:

```text
Laravel, Symfony, Express, NestJS, Fastify, Prologue, FastAPI, Spring Boot
```

The first thin adapter is available under
[adapters/laravel](adapters/laravel). It emits JSONL events from Laravel-style
commands, queue jobs, schedulers, and batch segments without capturing payloads.

You can run the Laravel adapter smoke example and generate a FlowCaptain report:

```bash
nimble laravelAdapterExample
```

## Human-Checkable Output

FlowCaptain should make example results easy to inspect. A user should be able
to run the example and inspect:

- `captain-report.md`
- `captain-report.html`
- `flow.mmd`
- `structure.mmd`
- `comparison.mmd`
- `manifest.json`

The HTML report is the easiest local inspection target because it opens directly
in a browser without Mermaid tooling. The generated reports should show:

- overall status
- flow diagram
- structure diagram
- timeline
- bottlenecks
- failures and retries
- variant comparison
- recommendation
- generated artifacts

## Dependencies and Notices

FlowCaptain uses FlowSurveyor as the analysis provider for generated reports.
Dependency license notes are kept in
[DEPENDENCY_NOTICES.md](DEPENDENCY_NOTICES.md).

## Changelog

Release notes are kept in [CHANGELOG.md](CHANGELOG.md).
