# Investigation Workflow

FlowCaptain supports both managed flows and externally observed flows. The main
workflow is designed for analysts who need to discover where the real bottleneck
lives.

## 1. Build The First Graph

Use hearing notes, architecture diagrams, job lists, database tables, logs, and
framework adapters to create the first node candidates. Connect only the arrows
that are meaningful for the question being investigated.

## 2. Measure The Current Flow

Collect start, finish, duration, retry, failure, skipped, wait, count, and
quality signals. A node can be measured by code instrumentation, framework
wrappers, log import, database records, OpenTelemetry spans, or manual records.

## 3. Read The Investigation Guidance

FlowCaptain reports candidate nodes and next investigation steps. Typical
suggestions are:

- increase granularity for the slowest or critical-path node
- investigate retry and failure causes before throughput tuning
- inspect handoff wait on arrows
- add missing telemetry for graph nodes that were not observed
- add owner and department metadata for follow-up work

## 4. Discuss With The Field

Bring the graph and report to the people who operate the flow. If they say a
node hides multiple kinds of work, split it. If they say the arrow is wrong,
change the graph and keep the previous version for comparison.

## 5. Improve And Compare

After changes, record another run and compare total time, critical path, wait,
retry, failure, throughput, defect rate, and first-pass yield. The goal is not a
local improvement; it is a better whole-flow result.
