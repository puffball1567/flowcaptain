import std/[json, strutils, tables]

import ./types
import ./toolkit

proc event(kind, flowId, runId, variantId, metricName: string;
    metricValue: float; unit = ""; nodeId = ""; edgeId = "";
    message = ""; tags = initOrderedTable[string, string]()): CaptainMetricEvent =
  CaptainMetricEvent(
    schemaVersion: 1,
    kind: kind,
    flowId: flowId,
    runId: runId,
    variantId: variantId,
    nodeId: nodeId,
    edgeId: edgeId,
    metricName: metricName,
    metricValue: metricValue,
    unit: unit,
    tags: tags,
    message: message
  )

proc runId(outcome: CaptainOutcome): string =
  outcome.run.planId & ":" & outcome.plan.variant

proc totalWorkMs(outcome: CaptainOutcome): int =
  for item in outcome.run.timeline:
    result.inc item.durationMs

proc totalWaitMs(outcome: CaptainOutcome): int =
  for item in outcome.survey.waitInsights:
    result.inc item.totalWaitMs

proc addTag(tags: var OrderedTable[string, string]; key, value: string) =
  tags[key] = value

proc metricEvents*(comparison: VariantComparison): seq[CaptainMetricEvent] =
  let selected =
    if comparison.betterVariant == comparison.candidate.plan.variant:
      comparison.candidate
    else:
      comparison.baseline
  let flowId = selected.plan.id
  let selectedRunId = selected.runId()
  let variant = selected.plan.variant
  let integrated = comparison.summarizeToolkitIntegration()

  var runTags = initOrderedTable[string, string]()
  runTags.addTag("selectedVariant", variant)
  runTags.addTag("baselineVariant", comparison.baseline.plan.variant)
  runTags.addTag("candidateVariant", comparison.candidate.plan.variant)
  runTags.addTag("betterVariant", comparison.betterVariant)

  result.add(event("run", flowId, selectedRunId, variant, "criticalPathMs",
    selected.analysis.criticalPathMs.float, "ms", tags = runTags,
    message = selected.analysis.criticalPath.join(" -> ")))
  result.add(event("run", flowId, selectedRunId, variant, "totalWorkMs",
    selected.totalWorkMs().float, "ms", tags = runTags))
  result.add(event("run", flowId, selectedRunId, variant, "elapsedMs",
    selected.run.totalMs.float, "ms", tags = runTags))
  result.add(event("run", flowId, selectedRunId, variant, "totalWaitMs",
    selected.totalWaitMs().float, "ms", tags = runTags))
  result.add(event("run", flowId, selectedRunId, variant, "retryCount",
    selected.analysis.retryCount.float, "count", tags = runTags))
  result.add(event("run", flowId, selectedRunId, variant, "failedNodeCount",
    selected.analysis.failedNodes.len.float, "count", tags = runTags))
  result.add(event("comparison", flowId, selectedRunId, variant,
    "criticalPathDeltaMs", comparison.deltaMs.float, "ms", tags = runTags,
    message = comparison.summary))

  for item in selected.run.timeline:
    var tags = initOrderedTable[string, string]()
    tags.addTag("status", $item.status)
    tags.addTag("critical", $(item.nodeId in selected.analysis.criticalPath))
    result.add(event("node", flowId, selectedRunId, variant, "durationMs",
      item.durationMs.float, "ms", nodeId = item.nodeId, tags = tags,
      message = item.message))
    result.add(event("node", flowId, selectedRunId, variant, "retries",
      item.retries.float, "count", nodeId = item.nodeId, tags = tags))

  for item in selected.survey.waitInsights:
    var tags = initOrderedTable[string, string]()
    tags.addTag("fromNode", item.fromNode)
    tags.addTag("toNode", item.toNode)
    tags.addTag("blockedCount", $item.blockedCount)
    result.add(event("edge", flowId, selectedRunId, variant, "waitMs",
      item.totalWaitMs.float, "ms", edgeId = item.edgeId, tags = tags,
      message = item.reason))
    result.add(event("edge", flowId, selectedRunId, variant, "averageWaitMs",
      item.averageWaitMs, "ms", edgeId = item.edgeId, tags = tags,
      message = item.reason))

  for item in selected.survey.parallelismOpportunities:
    var tags = initOrderedTable[string, string]()
    tags.addTag("critical", $item.onCriticalPath)
    tags.addTag("fanIn", $item.fanIn)
    tags.addTag("fanOut", $item.fanOut)
    result.add(event("opportunity", flowId, selectedRunId, variant,
      "parallelismScore", item.score, "score", nodeId = item.nodeId,
      tags = tags, message = item.reason))

  for item in selected.survey.failureImpacts:
    var tags = initOrderedTable[string, string]()
    tags.addTag("kind", item.kind)
    result.add(event("reliability", flowId, selectedRunId, variant,
      "failureImpactScore", item.score, "score", nodeId = item.targetId,
      tags = tags, message = item.reason))

  result.add(event("dataQuality", flowId, selectedRunId, variant,
    "metricDensity", integrated.logbookMetricDensity, "ratio"))
  result.add(event("dataQuality", flowId, selectedRunId, variant,
    "timingCoverage", integrated.logbookTimingCoverage, "percent"))
  result.add(event("dataQuality", flowId, selectedRunId, variant,
    "surveyRecommendationCount", selected.survey.recommendations.len.float,
    "count"))

proc toJson*(item: CaptainMetricEvent): JsonNode =
  var tags = newJObject()
  for key, value in item.tags:
    tags[key] = %value
  %*{
    "schemaVersion": item.schemaVersion,
    "kind": item.kind,
    "flowId": item.flowId,
    "runId": item.runId,
    "variantId": item.variantId,
    "nodeId": item.nodeId,
    "edgeId": item.edgeId,
    "metricName": item.metricName,
    "metricValue": item.metricValue,
    "unit": item.unit,
    "tags": tags,
    "message": item.message
  }

proc metricEventsJson*(comparison: VariantComparison): JsonNode =
  result = newJArray()
  for item in comparison.metricEvents():
    result.add(item.toJson())

proc metricEventsJsonLines*(comparison: VariantComparison): string =
  for item in comparison.metricEvents():
    if result.len > 0:
      result.add("\n")
    result.add($item.toJson())
