import std/[sequtils, strutils, tables]

import flowsurveyor as sv

import ./types as cap

proc flowStatus(status: cap.NodeStatus): sv.FlowStatus =
  case status
  of cap.nsPending: sv.fsPending
  of cap.nsSucceeded: sv.fsSucceeded
  of cap.nsFailed: sv.fsFailed
  of cap.nsSkipped: sv.fsSkipped

proc runByNode(run: cap.CaptainRun): Table[string, cap.NodeRun] =
  for item in run.timeline:
    result[item.nodeId] = item

proc toSurveyGraph*(plan: cap.CaptainPlan): sv.SurveyGraph =
  result = sv.initSurveyGraph(plan.id, variantId = plan.variant)
  for item in plan.nodes:
    result.nodes.add(sv.surveyNode(item.id, item.title, variantId = plan.variant))
  for item in plan.edges:
    result.edges.add(sv.surveyEdge(item.id, item.fromNode, item.toNode,
      variantId = plan.variant))

proc toSurveyEvents*(outcome: cap.CaptainOutcome): seq[sv.SurveyEvent] =
  let runs = outcome.run.runByNode()
  for item in outcome.run.timeline:
    var metrics: seq[sv.KeyValue] = @[]
    if item.retries > 0:
      metrics.add(sv.kv("retries", $item.retries))
    result.add(sv.surveyEvent(
      "node:" & outcome.plan.variant & ":" & item.nodeId,
      "flowcaptain",
      outcome.plan.id,
      outcome.run.planId & ":" & outcome.plan.variant,
      sv.sekNodeFinished,
      variantId = outcome.plan.variant,
      nodeId = item.nodeId,
      status = item.status.flowStatus(),
      durationMillis = Natural(item.durationMs),
      metrics = metrics,
      message = item.message
    ))

  for edge in outcome.plan.edges:
    if not runs.hasKey(edge.fromNode) or not runs.hasKey(edge.toNode):
      continue
    let source = runs[edge.fromNode]
    let target = runs[edge.toNode]
    let waitMs = max(0, target.startedMs - source.finishedMs)
    let edgeStatus =
      if target.status == cap.nsSkipped: sv.fsSkipped
      elif source.status == cap.nsFailed or target.status == cap.nsFailed: sv.fsFailed
      else: sv.fsSucceeded

    if waitMs > 0:
      result.add(sv.surveyEvent(
        "wait:" & outcome.plan.variant & ":" & edge.id,
        "flowcaptain",
        outcome.plan.id,
        outcome.run.planId & ":" & outcome.plan.variant,
        sv.sekEdgeWaiting,
        variantId = outcome.plan.variant,
        edgeId = edge.id,
        status = sv.fsRunning,
        durationMillis = Natural(waitMs)
      ))

    if edgeStatus == sv.fsSkipped or edgeStatus == sv.fsFailed:
      result.add(sv.surveyEvent(
        "blocked:" & outcome.plan.variant & ":" & edge.id,
        "flowcaptain",
        outcome.plan.id,
        outcome.run.planId & ":" & outcome.plan.variant,
        sv.sekEdgeBlocked,
        variantId = outcome.plan.variant,
        edgeId = edge.id,
        status = edgeStatus,
        durationMillis = Natural(waitMs)
      ))
    else:
      result.add(sv.surveyEvent(
        "edge:" & outcome.plan.variant & ":" & edge.id,
        "flowcaptain",
        outcome.plan.id,
        outcome.run.planId & ":" & outcome.plan.variant,
        sv.sekEdgeSatisfied,
        variantId = outcome.plan.variant,
        edgeId = edge.id,
        status = edgeStatus,
        durationMillis = Natural(target.durationMs + waitMs)
      ))


proc toCaptainOperationalSummary(item: sv.OperationalSummary): cap.CaptainOperationalSummary =
  cap.CaptainOperationalSummary(
    executionCount: int(item.executionCount),
    succeededCount: int(item.succeededCount),
    failedCount: int(item.failedCount),
    skippedCount: int(item.skippedCount),
    retryCount: int(item.retryCount),
    workUnits: item.workUnits,
    acceptedUnits: item.acceptedUnits,
    defectUnits: item.defectUnits,
    totalCycleTimeMs: int(item.totalCycleTimeMillis),
    averageCycleTimeMs: item.averageCycleTimeMillis,
    totalWaitMs: int(item.totalWaitTimeMillis),
    totalBlockedMs: int(item.totalBlockedTimeMillis),
    totalObservedMs: int(item.totalObservedTimeMillis),
    throughputPerHour: item.throughputPerHour,
    failureRate: item.failureRate,
    defectRate: item.defectRate,
    retryRate: item.retryRate,
    firstPassYield: item.firstPassYield
  )

proc toCaptainInsights(report: sv.SurveyReport): cap.CaptainSurveyInsights =
  for item in report.waitInsights:
    result.waitInsights.add(cap.CaptainWaitInsight(
      edgeId: item.edgeId,
      fromNode: item.fromNode,
      toNode: item.toNode,
      blockedCount: int(item.blockedCount),
      totalWaitMs: int(item.totalWaitMillis),
      averageWaitMs: item.averageWaitMillis,
      reason: item.reason
    ))
  for item in report.parallelismOpportunities:
    result.parallelismOpportunities.add(cap.CaptainParallelismOpportunity(
      nodeId: item.nodeId,
      fanIn: int(item.fanIn),
      fanOut: int(item.fanOut),
      observedDurationMs: int(item.observedDurationMillis),
      onCriticalPath: item.onCriticalPath,
      score: item.score,
      reason: item.reason
    ))
  for item in report.failureImpacts:
    result.failureImpacts.add(cap.CaptainFailureImpact(
      targetId: item.targetId,
      kind: item.kind,
      failureCount: int(item.failureCount),
      retryCount: int(item.retryCount),
      failedDurationMs: int(item.failedDurationMillis),
      retryDurationMs: int(item.retryDurationMillis),
      score: item.score,
      reason: item.reason
    ))
  result.operationalSummary = report.operationalSummary.toCaptainOperationalSummary()
  for item in report.recommendations:
    if item.reason notin result.recommendations:
      result.recommendations.add(item.reason)

proc flowWorkNote(value: string): string =
  value.replace("observed duration", "total observed work duration")
       .replace("observed flow metrics", "total observed work metrics")

proc attachSurveyor*(outcome: cap.CaptainOutcome): cap.CaptainOutcome =
  result = outcome
  let report = sv.survey(outcome.plan.toSurveyGraph(), outcome.toSurveyEvents())
  result.survey = report.toCaptainInsights()

proc compareWithSurveyor*(baseline, candidate: cap.CaptainOutcome): cap.VariantComparison =
  let surveyComparison = sv.compareVariants(baseline.plan.variant, candidate.plan.variant,
    baseline.toSurveyEvents() & candidate.toSurveyEvents())
  let delta = candidate.analysis.criticalPathMs - baseline.analysis.criticalPathMs
  var better = baseline.plan.variant
  if delta < 0:
    better = candidate.plan.variant
  elif delta == 0:
    better = "tie"

  var summary: string
  if delta < 0:
    summary = "Variant " & candidate.plan.variant & " reduced the critical path by " & $(-delta) & " ms."
  elif delta > 0:
    summary = "Variant " & candidate.plan.variant & " increased the critical path by " & $delta & " ms."
  else:
    summary = "Both variants have the same critical path duration."

  cap.VariantComparison(
    baseline: baseline.attachSurveyor(),
    candidate: candidate.attachSurveyor(),
    deltaMs: delta,
    betterVariant: better,
    summary: summary,
    surveySummary: surveyComparison.summary.flowWorkNote(),
    improvements: surveyComparison.improvements.mapIt(it.flowWorkNote()),
    regressions: surveyComparison.regressions.mapIt(it.flowWorkNote())
  )
