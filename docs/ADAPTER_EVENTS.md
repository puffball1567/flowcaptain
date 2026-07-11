# Adapter Event Integration

FlowCaptain adapters should start thin. A framework adapter does not need to
embed the FlowCaptain runtime or control application data flow. It can emit
JSON Lines events for the batch, job, queue, handler, or service segment being
measured.

This keeps production integration lightweight:

- do not capture return values
- do not capture payloads or personal data
- record timing, status, retry count, and a coarse error kind
- buffer events during the run when practical
- flush once at the end of the run
- generate HTML reports out of band

## Event Format

Each line is one JSON object.

```json
{"schemaVersion":1,"eventType":"nodeFinished","flowId":"billing","runId":"run-1","variantId":"A","nodeId":"calculate","timestampMs":1970,"durationMs":850,"status":"succeeded","retryCount":1}
```

Core fields:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Current version is `1`. |
| `eventType` | `runStarted`, `nodeStarted`, `nodeFinished`, `nodeFailed`, `nodeSkipped`, `edgeWaitObserved`, or `runFinished`. |
| `flowId` | Stable flow or batch name. |
| `runId` | One execution instance. |
| `variantId` | Optional flow variant, such as `A` or `B`. |
| `nodeId` | Step, handler, service, command, or job segment id. |
| `edgeId` | Dependency edge id for edge events. |
| `timestampMs` | Milliseconds from any stable clock source. |
| `durationMs` | Observed duration for the event. |
| `status` | `pending`, `succeeded`, `failed`, or `skipped`. |
| `retryCount` | Retries observed for the segment. |
| `errorKind` | Coarse non-sensitive error category. |
| `message` | Short non-sensitive note. |

## Generate A Report

```bash
nimble eventReportExample
```

After installing FlowCaptain, run the CLI directly:

```bash
flowcaptain_event_report \
  --plan examples/billing_plan.json \
  --events examples/billing_events.jsonl \
  --out reports/adapter \
  --run-id run-1
```

When working from this repository without installing the package, use the
`nimble eventReportExample` task because it wires the local FlowBrigade Toolkit
paths.

The easiest file to inspect is:

```text
reports/adapter/captain-report.html
```

## Planned Framework Adapter Order

```text
Laravel
Symfony
Express
NestJS
Fastify
Prologue
FastAPI
Spring Boot
```

Prologue is intentionally placed after Fastify rather than at the end. It
should appear as a real web-framework target alongside widely known
frameworks, which also creates a discovery path for Nim.
