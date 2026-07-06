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
- dry-run the execution order
- run or simulate work
- record events
- analyze bottlenecks and critical path
- compare at least two variants
- generate a Markdown report with Mermaid diagrams
- generate a package manifest

## Human-Checkable Output

FlowCaptain should make example results easy to inspect. A user should be able
to run the example and inspect:

- `captain-report.md`
- `flow.mmd`
- `comparison.mmd`
- `manifest.json`

The Markdown report should show:

- overall status
- flow diagram
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
