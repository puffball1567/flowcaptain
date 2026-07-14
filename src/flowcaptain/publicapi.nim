import std/[json, os, strutils, tables, times]

import flowbrigade as fb

import ./adapterevents
import ./analysis
import ./compare
import ./health
import ./history
import ./historystore
import ./ids
import ./jsonio
import ./mermaid
import ./metrics
import ./plandiff
import ./report
import ./rotation
import ./surveyor
import ./toolkit
import ./types
import ./validation

type
  CaptainGraphSummary* = object
    sources*: seq[string]
    sinks*: seq[string]
    batches*: seq[seq[string]]

  CaptainControlBridgeReport* = object
    ok*: bool
    flowId*: string
    policyPlanName*: string
    flowBrigadePlan*: fb.FlowBrigadePlanReport
    errors*: seq[string]

  CaptainControlDecision* = object
    policyName*: string
    key*: string
    cost*: int
    allowed*: bool
    limit*: int
    remaining*: int
    retryAfterMs*: int64
    resetAfterMs*: int64


proc capabilityKindText(kind: fb.FlowBrigadeCapabilityKind): string =
  case kind
  of fb.fbckBackoff: "backoff"
  of fb.fbckRetry: "retry"
  of fb.fbckRateLimit: "rateLimit"
  of fb.fbckKeyedRateLimit: "keyedRateLimit"
  of fb.fbckCircuitBreaker: "circuitBreaker"
  of fb.fbckBulkhead: "bulkhead"
  of fb.fbckLockLease: "lockLease"
  of fb.fbckBudget: "budget"
  of fb.fbckTimeoutDeadline: "timeoutDeadline"
  of fb.fbckThrottleDebounce: "throttleDebounce"
  of fb.fbckFallback: "fallback"
  of fb.fbckObservability: "observability"
  of fb.fbckControlDiagnostics: "controlDiagnostics"

proc policyIssueKindText(kind: fb.FlowPolicyValidationIssueKind): string =
  case kind
  of fb.fpviMissingPrimaryLimiter: "missingPrimaryLimiter"
  of fb.fpviMissingLimiter: "missingLimiter"
  of fb.fpviInvalidQuota: "invalidQuota"
  of fb.fpviInvalidRetry: "invalidRetry"
  of fb.fpviInvalidCircuitBreaker: "invalidCircuitBreaker"
  of fb.fpviInvalidBulkhead: "invalidBulkhead"

proc capabilityJson(capability: fb.FlowBrigadeCapability): JsonNode =
  %*{
    "kind": capability.kind.capabilityKindText(),
    "stable": capability.stable,
    "description": capability.description
  }

proc policyValidationJson(report: fb.FlowPolicyValidationReport): JsonNode =
  result = %*{
    "valid": report.valid,
    "policyName": report.policyName,
    "limiterCount": report.limiterCount,
    "hasQuota": report.hasQuota,
    "hasRetry": report.hasRetry,
    "hasCircuitBreaker": report.hasCircuitBreaker,
    "hasBulkhead": report.hasBulkhead,
    "issues": []
  }
  for issue in report.issues:
    result["issues"].add(%*{
      "kind": issue.kind.policyIssueKindText(),
      "path": issue.path,
      "message": issue.message
    })

proc flowBrigadePlanReportJson(report: fb.FlowBrigadePlanReport): JsonNode =
  result = %*{
    "ok": report.ok,
    "name": report.name,
    "capabilities": [],
    "policyReports": [],
    "errors": []
  }
  for capability in report.capabilities:
    result["capabilities"].add(capability.capabilityJson())
  for policyReport in report.policyReports:
    result["policyReports"].add(policyReport.policyValidationJson())
  for item in report.errors:
    result["errors"].add(%item)

proc validateControlBridge*(plan: CaptainPlan;
    controlPlan: fb.FlowBrigadePlan): CaptainControlBridgeReport =
  let planValidation = validate(plan)
  let controlReport = fb.validate(controlPlan)
  result = CaptainControlBridgeReport(
    ok: planValidation.ok and controlReport.ok,
    flowId: plan.id,
    policyPlanName: controlPlan.name,
    flowBrigadePlan: controlReport
  )
  for item in planValidation.errors:
    result.errors.add("flow plan: " & item)
  for item in controlReport.errors:
    result.errors.add("control plan: " & item)

proc controlBridgeJson*(report: CaptainControlBridgeReport): JsonNode =
  result = %*{
    "schemaVersion": 1,
    "ok": report.ok,
    "flowId": report.flowId,
    "policyPlanName": report.policyPlanName,
    "flowBrigadePlan": report.flowBrigadePlan.flowBrigadePlanReportJson(),
    "errors": []
  }
  for item in report.errors:
    result["errors"].add(%item)

proc flowBrigadeCapabilitiesJson*(): JsonNode =
  result = newJArray()
  for capability in fb.flowBrigadeCapabilities():
    result.add(capability.capabilityJson())

proc toCaptainControlDecision(policy: fb.FlowPolicy; key: string; cost: int;
    decision: fb.RateLimitResult): CaptainControlDecision =
  CaptainControlDecision(
    policyName: policy.name,
    key: key,
    cost: cost,
    allowed: decision.allowed,
    limit: decision.limit,
    remaining: decision.remaining,
    retryAfterMs: decision.retryAfter.inMilliseconds,
    resetAfterMs: decision.resetAfter.inMilliseconds
  )

proc inspectControlPolicy*(policy: fb.FlowPolicy; key: string; cost = 1):
    CaptainControlDecision =
  policy.toCaptainControlDecision(key, cost, fb.inspect(policy, key, cost))

proc allowControlPolicy*(policy: fb.FlowPolicy; key: string; cost = 1):
    CaptainControlDecision =
  policy.toCaptainControlDecision(key, cost, fb.consume(policy, key, cost))

proc controlDecisionJson*(decision: CaptainControlDecision): JsonNode =
  %*{
    "schemaVersion": 1,
    "policyName": decision.policyName,
    "key": decision.key,
    "cost": decision.cost,
    "allowed": decision.allowed,
    "limit": decision.limit,
    "remaining": decision.remaining,
    "retryAfterMs": decision.retryAfterMs,
    "resetAfterMs": decision.resetAfterMs
  }

proc loadPlanJson*(content: string): CaptainPlan =
  parseJson(content).planFromJson()

proc savePlanJson*(plan: CaptainPlan): string =
  $plan.toJson()

proc normalizePlan*(plan: CaptainPlan): CaptainPlan =
  result = plan
  result.id = normalizeSharedId(plan.id)
  result.variant = normalizeSharedId(plan.variant)
  for item in result.nodes.mitems:
    item.id = normalizeSharedId(item.id)
  for item in result.edges.mitems:
    item.id = normalizeSharedId(item.id)
    item.fromNode = normalizeSharedId(item.fromNode)
    item.toNode = normalizeSharedId(item.toNode)

proc validatePlan*(plan: CaptainPlan): ValidationResult =
  validate(plan)

proc validationJson(value: ValidationResult): JsonNode =
  result = %*{
    "schemaVersion": 1,
    "ok": value.ok,
    "errors": []
  }
  for item in value.errors:
    result["errors"].add(%item)

proc validatePlanJson*(planJson: string): JsonNode =
  loadPlanJson(planJson).validatePlan().validationJson()

proc dryRunPlan*(plan: CaptainPlan): DryRun =
  plan.dependencyDryRun()

proc dryRunJson(value: DryRun): JsonNode =
  result = %*{
    "schemaVersion": 1,
    "ok": value.ok,
    "batches": [],
    "errors": []
  }
  for batch in value.batches:
    var nodes = newJArray()
    for nodeId in batch:
      nodes.add(%nodeId)
    result["batches"].add(nodes)
  for item in value.errors:
    result["errors"].add(%item)

proc dryRunPlanJson*(planJson: string): JsonNode =
  loadPlanJson(planJson).dryRunPlan().dryRunJson()

proc dependencyBatches*(plan: CaptainPlan): seq[seq[string]] =
  let dry = plan.dryRunPlan()
  if not dry.ok:
    raise newException(ValueError, dry.errors.join("; "))
  dry.batches

proc graphSummary*(plan: CaptainPlan): CaptainGraphSummary =
  let dry = plan.dryRunPlan()
  result.batches = dry.batches

  var incoming = initCountTable[string]()
  var outgoing = initCountTable[string]()
  for item in plan.nodes:
    incoming.inc(item.id, 0)
    outgoing.inc(item.id, 0)
  for item in plan.edges:
    incoming.inc(item.toNode)
    outgoing.inc(item.fromNode)

  for item in plan.nodes:
    if incoming[item.id] == 0:
      result.sources.add(item.id)
    if outgoing[item.id] == 0:
      result.sinks.add(item.id)

proc graphSummaryJson*(plan: CaptainPlan): JsonNode =
  let summary = plan.graphSummary()
  result = %*{
    "schemaVersion": 1,
    "sources": [],
    "sinks": [],
    "batches": []
  }
  for item in summary.sources:
    result["sources"].add(%item)
  for item in summary.sinks:
    result["sinks"].add(%item)
  for batch in summary.batches:
    var nodes = newJArray()
    for nodeId in batch:
      nodes.add(%nodeId)
    result["batches"].add(nodes)

proc enrichOutcome(outcome: CaptainOutcome): CaptainOutcome =
  if not outcome.dryRun.ok:
    return outcome
  outcome.complete().attachSurveyor()

proc executePlan*(plan: CaptainPlan): CaptainOutcome =
  plan.executeWithToolkit().enrichOutcome()

proc simulatePlan*(plan: CaptainPlan): CaptainOutcome =
  plan.executePlan()

proc analyzeRun*(plan: CaptainPlan; run: CaptainRun): CaptainOutcome =
  CaptainOutcome(plan: plan, dryRun: plan.dryRunPlan(), run: run).enrichOutcome()

proc importEventsJsonl*(content: string): seq[CaptainAdapterEvent] =
  parseAdapterEventsJsonLines(content)

proc exportEventsJsonl*(events: openArray[CaptainAdapterEvent]): string =
  adapterEventsJsonLines(events)

proc validateAdapterEventsContract*(events: openArray[CaptainAdapterEvent]):
    AdapterContractReport =
  validateAdapterContract(events)

proc validateAdapterEventsContractJsonl*(content: string):
    AdapterContractReport =
  validateAdapterContractJsonl(content)

proc adapterContractJson*(report: AdapterContractReport): JsonNode =
  adapterContractReportJson(report)

proc buildOutcomeFromEvents*(plan: CaptainPlan;
    events: openArray[CaptainAdapterEvent]): CaptainOutcome =
  plan.outcomeFromAdapterEvents(events).enrichOutcome()

proc analyzeAdapterEvents*(plan: CaptainPlan;
    events: openArray[CaptainAdapterEvent]): CaptainOutcome =
  plan.buildOutcomeFromEvents(events)

proc analyzeAdapterEventsJsonl*(plan: CaptainPlan; eventsJsonl: string):
    CaptainOutcome =
  plan.analyzeAdapterEvents(importEventsJsonl(eventsJsonl))

proc statusText(status: NodeStatus): string =
  case status
  of nsPending: "pending"
  of nsSucceeded: "succeeded"
  of nsFailed: "failed"
  of nsSkipped: "skipped"

proc runJson(run: CaptainRun): JsonNode =
  result = %*{
    "planId": run.planId,
    "variant": run.variant,
    "ok": run.ok,
    "totalMs": run.totalMs,
    "timeline": [],
    "errors": []
  }
  for item in run.timeline:
    result["timeline"].add(%*{
      "nodeId": item.nodeId,
      "title": item.title,
      "status": item.status.statusText(),
      "startedMs": item.startedMs,
      "finishedMs": item.finishedMs,
      "durationMs": item.durationMs,
      "retries": item.retries,
      "message": item.message
    })
  for item in run.errors:
    result["errors"].add(%item)

proc analysisJson(analysis: CaptainAnalysis): JsonNode =
  result = %*{
    "criticalPath": [],
    "criticalPathMs": analysis.criticalPathMs,
    "slowestNode": analysis.slowestNode,
    "slowestNodeMs": analysis.slowestNodeMs,
    "failedNodes": [],
    "retryCount": analysis.retryCount,
    "recommendation": analysis.recommendation
  }
  for item in analysis.criticalPath:
    result["criticalPath"].add(%item)
  for item in analysis.failedNodes:
    result["failedNodes"].add(%item)

proc operationalSummaryJson(summary: CaptainOperationalSummary): JsonNode =
  %*{
    "executionCount": summary.executionCount,
    "succeededCount": summary.succeededCount,
    "failedCount": summary.failedCount,
    "skippedCount": summary.skippedCount,
    "retryCount": summary.retryCount,
    "workUnits": summary.workUnits,
    "acceptedUnits": summary.acceptedUnits,
    "defectUnits": summary.defectUnits,
    "totalCycleTimeMs": summary.totalCycleTimeMs,
    "averageCycleTimeMs": summary.averageCycleTimeMs,
    "totalWaitMs": summary.totalWaitMs,
    "totalBlockedMs": summary.totalBlockedMs,
    "totalObservedMs": summary.totalObservedMs,
    "throughputPerHour": summary.throughputPerHour,
    "failureRate": summary.failureRate,
    "defectRate": summary.defectRate,
    "retryRate": summary.retryRate,
    "firstPassYield": summary.firstPassYield
  }

proc surveyJson(survey: CaptainSurveyInsights): JsonNode =
  result = %*{
    "waitInsights": [],
    "parallelismOpportunities": [],
    "failureImpacts": [],
    "operationalSummary": survey.operationalSummary.operationalSummaryJson(),
    "recommendations": []
  }
  for item in survey.waitInsights:
    result["waitInsights"].add(%*{
      "edgeId": item.edgeId,
      "fromNode": item.fromNode,
      "toNode": item.toNode,
      "blockedCount": item.blockedCount,
      "totalWaitMs": item.totalWaitMs,
      "averageWaitMs": item.averageWaitMs,
      "reason": item.reason
    })
  for item in survey.parallelismOpportunities:
    result["parallelismOpportunities"].add(%*{
      "nodeId": item.nodeId,
      "fanIn": item.fanIn,
      "fanOut": item.fanOut,
      "observedDurationMs": item.observedDurationMs,
      "onCriticalPath": item.onCriticalPath,
      "score": item.score,
      "reason": item.reason
    })
  for item in survey.failureImpacts:
    result["failureImpacts"].add(%*{
      "targetId": item.targetId,
      "kind": item.kind,
      "failureCount": item.failureCount,
      "retryCount": item.retryCount,
      "failedDurationMs": item.failedDurationMs,
      "retryDurationMs": item.retryDurationMs,
      "score": item.score,
      "reason": item.reason
    })
  for item in survey.recommendations:
    result["recommendations"].add(%item)

proc outcomeJson*(outcome: CaptainOutcome): JsonNode =
  %*{
    "schemaVersion": 1,
    "plan": outcome.plan.toJson(),
    "dryRun": outcome.dryRun.dryRunJson(),
    "run": outcome.run.runJson(),
    "analysis": outcome.analysis.analysisJson(),
    "survey": outcome.survey.surveyJson(),
    "health": outcome.health().toJson()
  }

proc snapshotRun*(outcome: CaptainOutcome; runId = "";
    recordedAtMs = 0): CaptainHistorySnapshot =
  historySnapshot(outcome, runId = runId, recordedAtMs = recordedAtMs)

proc snapshotJson*(snapshot: CaptainHistorySnapshot): JsonNode =
  snapshot.toJson()

proc historyJsonl*(snapshots: openArray[CaptainHistorySnapshot]): string =
  historySnapshotsJsonLines(snapshots)

proc importHistoryJsonl*(content: string): seq[CaptainHistorySnapshot] =
  parseHistorySnapshotsJsonLines(content)

proc historyTrendReport*(snapshots: openArray[CaptainHistorySnapshot]):
    CaptainHistoryTrend =
  historyTrend(snapshots)

proc historyTrendJson*(snapshots: openArray[CaptainHistorySnapshot]): JsonNode =
  snapshots.historyTrend().toJson()

proc appendHistoryFile*(path: string; snapshot: CaptainHistorySnapshot) =
  appendHistorySnapshotFile(path, snapshot)

proc writeHistoryFile*(path: string;
    snapshots: openArray[CaptainHistorySnapshot]) =
  writeHistorySnapshotsFile(path, snapshots)

proc loadHistoryFile*(path: string): seq[CaptainHistorySnapshot] =
  loadHistorySnapshotsFile(path)

proc appendHistorySqlite*(path: string; snapshot: CaptainHistorySnapshot) =
  appendHistorySnapshotSqlite(path, snapshot)

proc loadHistorySqlite*(path: string; flowId = ""):
    seq[CaptainHistorySnapshot] =
  loadHistorySnapshotsSqlite(path, flowId = flowId)

proc executePlanJson*(planJson: string): JsonNode =
  loadPlanJson(planJson).executePlan().outcomeJson()

proc analyzeAdapterEventsJson*(planJson, eventsJsonl: string): JsonNode =
  loadPlanJson(planJson).analyzeAdapterEventsJsonl(eventsJsonl).outcomeJson()

proc comparePlanVariants*(baseline, candidate: CaptainPlan): VariantComparison =
  compare(baseline.executePlan(), candidate.executePlan())

proc comparePlanVariantsJson*(baselineJson, candidateJson: string): JsonNode =
  let comparison = comparePlanVariants(loadPlanJson(baselineJson),
                                       loadPlanJson(candidateJson))
  result = %*{
    "schemaVersion": 1,
    "baseline": comparison.baseline.outcomeJson(),
    "candidate": comparison.candidate.outcomeJson(),
    "deltaMs": comparison.deltaMs,
    "betterVariant": comparison.betterVariant,
    "summary": comparison.summary,
    "surveySummary": comparison.surveySummary,
    "improvements": [],
    "regressions": []
  }
  for item in comparison.improvements:
    result["improvements"].add(%item)
  for item in comparison.regressions:
    result["regressions"].add(%item)

proc diffPlanJson*(baselineJson, candidateJson: string): JsonNode =
  diffPlans(loadPlanJson(baselineJson), loadPlanJson(candidateJson)).toJson()

proc flowHealth*(outcome: CaptainOutcome): FlowHealth =
  outcome.health()

proc flowHealthJson*(planJson, eventsJsonl: string): JsonNode =
  analyzeAdapterEventsJson(planJson, eventsJsonl)["health"]

proc metricEventsFor*(comparison: VariantComparison): seq[CaptainMetricEvent] =
  comparison.metricEvents()

proc metricEventsJsonFor*(comparison: VariantComparison): JsonNode =
  comparison.metricEventsJson()

proc metricEventsJsonLinesFor*(comparison: VariantComparison): string =
  comparison.metricEventsJsonLines()

proc reportArtifacts*(comparison: VariantComparison): CaptainArtifacts =
  artifacts(comparison)

proc reportArtifactsJson*(comparison: VariantComparison): JsonNode =
  comparison.reportArtifacts().toJson()

proc generateReports*(comparison: VariantComparison): CaptainArtifacts =
  comparison.reportArtifacts()

proc generateReportsFromAdapterEvents*(plan: CaptainPlan;
    events: openArray[CaptainAdapterEvent]): CaptainArtifacts =
  let outcome = plan.analyzeAdapterEvents(events)
  let comparison = VariantComparison(
    baseline: outcome,
    candidate: outcome,
    deltaMs: 0,
    betterVariant: outcome.plan.variant,
    summary: "Adapter event import completed.",
    surveySummary: "Adapter event import completed."
  )
  comparison.generateReports()

proc generateReportsFromAdapterEventsJson*(planJson, eventsJsonl: string): JsonNode =
  loadPlanJson(planJson).generateReportsFromAdapterEvents(
    importEventsJsonl(eventsJsonl)).toJson()

proc writeReports*(comparison: VariantComparison; rootDir = "reports";
    runId = ""; retentionDays: Natural = 30; keepLatest = true): ReportWriteResult =
  writeRotatedReports(comparison.generateReports(),
    defaultReportRotationOptions(rootDir = rootDir, runId = runId,
      retentionDays = retentionDays, keepLatest = keepLatest))

proc writeReportsFromAdapterEvents*(plan: CaptainPlan;
    events: openArray[CaptainAdapterEvent]; rootDir = "reports"; runId = "";
    retentionDays: Natural = 30; keepLatest = true): ReportWriteResult =
  writeRotatedReports(plan.generateReportsFromAdapterEvents(events),
    defaultReportRotationOptions(rootDir = rootDir, runId = runId,
      retentionDays = retentionDays, keepLatest = keepLatest))

proc flowDiagram*(outcome: CaptainOutcome): string =
  outcome.mermaid()

proc structureDiagram*(outcome: CaptainOutcome): string =
  outcome.structureMermaid()

proc comparisonDiagram*(comparison: VariantComparison): string =
  comparison.comparisonMermaid()

proc ensureParent(path: string) =
  let parent = path.splitPath.head
  if parent.len > 0:
    createDir(parent)

proc exportMetricEventsJsonl*(comparison: VariantComparison; path: string) =
  ensureParent(path)
  writeFile(path, comparison.metricEventsJsonLines())

proc exportAdapterEventsJsonl*(events: openArray[CaptainAdapterEvent]; path: string) =
  ensureParent(path)
  writeFile(path, exportEventsJsonl(events))
