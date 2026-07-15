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
- validate shared FlowBrigade Toolkit ids
- compare plan structure changes before and after optimization
- score flow health for reliability and optimization readiness

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
nimble leak
```

`nimble leak` builds the ARC release leak probe and runs it under Valgrind,
failing on definite or indirect leaks.

The latest verification record is kept in
[docs/VERIFICATION.md](docs/VERIFICATION.md).

## Toolkit Execution

FlowCaptain can execute a plan through the lower-level toolkit pieces:

```nim
import flowcaptain

var plan = initCaptainPlan("daily", "Daily")
plan.nodes.add(node("extract", "Extract", expectedMs = 10))
plan.nodes.add(node("publish", "Publish", expectedMs = 20))
plan.edges.add(edge("extract-publish", "extract", "publish"))

let outcome = plan.executeWithToolkit().complete()
```

`executeWithToolkit` uses FlowDependency for dependency-ready batches and
FlowWorkRunner for execution. For production work, pass a
`WorkExecutorRegistry` with executors for each node.

## Public Integration API

FlowCaptain is the public bridge for the FlowBrigade Toolkit. External
adapters and future language bindings do not need to call every lower-level
toolkit package directly. They can call FlowCaptain's integration API and let
FlowCaptain delegate to FlowDependency, FlowWorkRunner, FlowLogbook,
FlowSurveyor, and FlowGarage, while preserving FlowBrigade-compatible retry
and control signals for reports and future policy bridges.

```nim
import flowcaptain

let plan = loadPlanJson(readFile("plan.json"))
let events = importEventsJsonl(readFile("events.jsonl"))

let outcome = analyzeAdapterEvents(plan, events)
let output = generateReportsFromAdapterEvents(plan, events)
```

The integration API intentionally keeps responsibilities separate:

- FlowDependency remains responsible for graph structure and dependency-ready
  batches.
- FlowWorkRunner remains responsible for execution integration.
- FlowSurveyor remains responsible for bottleneck, wait, failure, and
  operational analysis.
- FlowGarage remains responsible for report bundle conversion.
- FlowBrigade remains the policy/runtime-control layer; FlowCaptain currently
  carries compatible retry and control evidence through outcomes and reports.
- FlowCaptain coordinates these pieces and exposes stable entry points for
  adapters, CLIs, and future C ABI bindings.

Useful entry points include:

- `loadPlanJson` / `savePlanJson`
- `normalizePlan` / `validatePlan` / `validatePlanJson`
- `dryRunPlan` / `dependencyBatches`
- `executePlan` / `simulatePlan`
- `importEventsJsonl` / `exportEventsJsonl`
- `validateAdapterContract` / `validateAdapterContractJsonl`
- `analyzeAdapterEvents` / `generateReportsFromAdapterEvents`
- `generateReports` / `writeReports`
- `diffPlanJson` / `comparePlanVariants`
- `historySnapshot` / `historySnapshotsJsonLines` / `historyTrend`
- `appendHistorySnapshotFile` / `loadHistorySnapshotsFile` for local JSONL history
- `appendHistorySnapshotSqlite` / `loadHistorySnapshotsSqlite` for SQLite history
- `flowHealth` / `flowHealthJson`
- `metricEventsFor` / `metricEventsJsonLinesFor`
- `flowDiagram` / `structureDiagram` / `comparisonDiagram`
- `validateControlBridge` / `allowControlPolicy` / `inspectControlPolicy` for FlowBrigade policy bridges

This means framework adapters should not stop at writing JSONL. A complete
adapter can collect safe events, build or load a plan, call FlowCaptain through
the public API or CLI, and produce the same reports, metrics, health score,
variant comparison, and artifacts available to native Nim users.

## Integration Primitives

FlowCaptain exposes small primitives that are useful across the toolkit:

- `checkSharedId` and `normalizeSharedId` keep `flowId`, `runId`, `nodeId`,
  `edgeId`, `artifactId`, and `policyId` compatible across repositories.
- `diffPlans` reports node and edge changes between two flow definitions,
  including breaking removals and wait-on changes.
- `health` converts run, survey, retry, wait, and critical-path signals into a
  single score plus reasons.

These are deliberately independent from any specific web framework or workflow
engine. They are meant to make FlowCaptain useful for both executed flows and
externally observed business flows.


## Flow Investigation Method

FlowCaptain is also a flow investigation tool. It can start from hearing notes,
existing jobs, methods, database tables, logs, and adapter events, then help an
analyst decide which nodes to connect, measure, split, or refine.

See:

- [docs/METHODOLOGY.md](docs/METHODOLOGY.md)
- [docs/NODE_DESIGN_GUIDE.md](docs/NODE_DESIGN_GUIDE.md)
- [docs/INVESTIGATION_WORKFLOW.md](docs/INVESTIGATION_WORKFLOW.md)

## Run History

FlowCaptain can turn each analyzed run into a compact history snapshot. Callers
can store the JSONL in a database, object storage, or a batch artifact directory
and compare the latest run with the previous run.

```nim
let outcome = analyzeAdapterEvents(plan, events)
let snapshot = historySnapshot(outcome, runId = "billing-2026-07-13")
let jsonl = historySnapshotsJsonLines(@[snapshot])
appendHistorySnapshotFile("reports/history.jsonl", snapshot)
appendHistorySnapshotSqlite("reports/history.sqlite3", snapshot)
```

`historyTrend` compares the latest two snapshots and reports critical-path,
work, wait, retry, failure, health, cycle-time, throughput, and yield changes.
This is the core PDCA loop: record a run, change the flow, record the next run,
then check whether the whole flow improved or merely moved the bottleneck.

## Adapter Events

Framework adapters can start with lightweight JSON Lines events instead of
embedding FlowCaptain deeply into application code. This is intended for web
batch, job, queue, and scheduled-task instrumentation.

```json
{"schemaVersion":1,"eventType":"nodeFinished","flowId":"billing","runId":"run-1","variantId":"A","nodeId":"calculate","durationMs":850,"status":"succeeded","retryCount":1}
```

FlowCaptain can parse these events with `parseAdapterEventsJsonLines`, validate
the shared adapter contract with `validateAdapterContract`, and turn them into
an analyzable outcome with `outcomeFromAdapterEvents`.

The CLI can generate browser-readable reports from a plan JSON and adapter
event JSONL:

```bash
nimble eventReportExample
```

See [docs/ADAPTER_EVENTS.md](docs/ADAPTER_EVENTS.md) for the event format,
compatibility contract, production notes, and adapter order.

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
