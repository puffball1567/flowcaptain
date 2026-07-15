import std/[algorithm, json, strutils, tables]

import ./types

const InvestigationSchemaVersion* = 1

proc statusText(status: NodeStatus): string =
  case status
  of nsPending: "pending"
  of nsSucceeded: "succeeded"
  of nsFailed: "failed"
  of nsSkipped: "skipped"

proc meta(item: CaptainNode; keys: openArray[string]; fallback: string): string =
  for key in keys:
    if item.metadata.hasKey(key) and item.metadata[key].strip().len > 0:
      return item.metadata[key].strip()
  fallback

proc confidence(item: CaptainNode; observed: bool): float =
  let raw = item.meta(["confidence", "investigation.confidence"], "")
  if raw.len > 0:
    try:
      return clamp(parseFloat(raw), 0.0, 1.0)
    except ValueError:
      discard
  if observed: 0.80 else: 0.45

proc timelineByNode(outcome: CaptainOutcome): Table[string, NodeRun] =
  for item in outcome.run.timeline:
    result[item.nodeId] = item

proc addSuggestion(report: var InvestigationReport; targetId, kind, reason,
    nextStep: string; priority: int) =
  for item in report.suggestions:
    if item.targetId == targetId and item.kind == kind:
      return
  report.suggestions.add(InvestigationSuggestion(priority: priority,
    targetId: targetId, kind: kind, reason: reason, nextStep: nextStep))

proc sortSuggestions(report: var InvestigationReport) =
  report.suggestions.sort(proc (a, b: InvestigationSuggestion): int =
    let byPriority = cmp(a.priority, b.priority)
    if byPriority != 0: byPriority else: cmp(a.targetId, b.targetId))

proc investigationReport*(outcome: CaptainOutcome): InvestigationReport =
  let runs = outcome.timelineByNode()
  result = InvestigationReport(
    flowId: outcome.plan.id,
    runId: outcome.run.planId,
    variantId: outcome.plan.variant,
    summary: "Flow investigation candidates and next-step suggestions."
  )

  for item in outcome.plan.nodes:
    let observed = runs.hasKey(item.id)
    var reason = "candidate from plan definition"
    if observed:
      let run = runs[item.id]
      reason = "observed as " & run.status.statusText() & " in this run"
      if item.id in outcome.analysis.criticalPath:
        reason.add(" and lies on the critical path")
    result.candidates.add(InvestigationNodeCandidate(
      nodeId: item.id,
      title: item.title,
      kind: item.meta(["kind", "nodeKind", "investigation.kind"], "process"),
      owner: item.meta(["owner", "team", "investigation.owner"], ""),
      department: item.meta(["department", "dept", "investigation.department"], ""),
      source: item.meta(["source", "instrumentation", "investigation.source"], "plan"),
      granularity: item.meta(["granularity", "investigation.granularity"], "normal"),
      confidence: item.confidence(observed),
      observed: observed,
      reason: reason
    ))

    if not observed:
      result.addSuggestion(item.id, "missingTelemetry",
        "The node exists in the investigation graph but no execution event was observed.",
        "Connect an adapter, log importer, or manual measurement source for this node.", 20)
    if item.meta(["owner", "team", "investigation.owner"], "").len == 0:
      result.addSuggestion(item.id, "missingOwner",
        "No owner is attached to this node, which weakens follow-up investigation.",
        "Add owner or team metadata during hearing or node review.", 80)
    if item.meta(["department", "dept", "investigation.department"], "").len == 0:
      result.addSuggestion(item.id, "missingDepartment",
        "No department is attached to this node, which weakens cross-functional analysis.",
        "Add department metadata when the node maps to business or operational work.", 85)

  if outcome.analysis.failedNodes.len > 0:
    for nodeId in outcome.analysis.failedNodes:
      result.addSuggestion(nodeId, "reliabilityInvestigation",
        "This node failed and can block downstream flow analysis.",
        "Capture error kind, input volume, retry count, and handoff context before speed tuning.", 1)

  if outcome.analysis.retryCount > 0:
    for item in outcome.run.timeline:
      if item.retries > 0:
        result.addSuggestion(item.nodeId, "retryInvestigation",
          "Retries create hidden rework and can make average duration misleading.",
          "Break down retry causes and compare first-pass yield before and after changes.", 5)

  if outcome.analysis.slowestNode.len > 0:
    let critical = outcome.analysis.slowestNode in outcome.analysis.criticalPath
    result.addSuggestion(outcome.analysis.slowestNode, "granularityIncrease",
      "The slowest observed node" & (if critical: " is on the critical path." else: " may hide inner work."),
      "Split this node into method, query, API, queue, or manual-work subnodes for the next run.",
      if critical: 10 else: 30)

  for wait in outcome.survey.waitInsights:
    if wait.totalWaitMs > 0 or wait.blockedCount > 0:
      result.addSuggestion(wait.edgeId, "handoffInvestigation",
        "This arrow has observed wait or blocking and may represent queue, approval, or dependency delay.",
        "Record source finish, target start, queue depth, owner handoff, and wait-on semantics.", 15)

  if result.suggestions.len == 0:
    result.addSuggestion(outcome.plan.id, "collectBaseline",
      "No strong investigation target was detected from this run.",
      "Collect another comparable run or add business-volume metrics before changing the graph.", 90)

  result.sortSuggestions()
  if result.candidates.len > 0:
    result.summary = $result.candidates.len & " node candidates and " &
      $result.suggestions.len & " investigation suggestions."

proc toJson*(candidate: InvestigationNodeCandidate): JsonNode =
  %*{
    "nodeId": candidate.nodeId,
    "title": candidate.title,
    "kind": candidate.kind,
    "owner": candidate.owner,
    "department": candidate.department,
    "source": candidate.source,
    "granularity": candidate.granularity,
    "confidence": candidate.confidence,
    "observed": candidate.observed,
    "reason": candidate.reason
  }

proc toJson*(suggestion: InvestigationSuggestion): JsonNode =
  %*{
    "priority": suggestion.priority,
    "targetId": suggestion.targetId,
    "kind": suggestion.kind,
    "reason": suggestion.reason,
    "nextStep": suggestion.nextStep
  }

proc toJson*(report: InvestigationReport): JsonNode =
  result = %*{
    "schemaVersion": InvestigationSchemaVersion,
    "flowId": report.flowId,
    "runId": report.runId,
    "variantId": report.variantId,
    "summary": report.summary,
    "candidates": [],
    "suggestions": []
  }
  for item in report.candidates:
    result["candidates"].add(item.toJson())
  for item in report.suggestions:
    result["suggestions"].add(item.toJson())
