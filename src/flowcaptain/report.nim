import std/[algorithm, strutils, tables]

import ./types
import ./mermaid
import ./jsonio
import ./toolkit
import ./health

proc statusText(status: NodeStatus): string =
  case status
  of nsPending: "pending"
  of nsSucceeded: "ok"
  of nsFailed: "failed"
  of nsSkipped: "skipped"

proc joinPath(path: seq[string]): string =
  if path.len == 0:
    "(none)"
  else:
    path.join(" -> ")

proc boolText(value: bool): string =
  if value: "yes" else: "no"

proc kindText(kind: EdgeKind): string =
  case kind
  of ekRequired: "required"
  of ekOptional: "optional"

proc cell(value: string): string =
  value.replace("|", "\\|").replace("\n", " ")

proc html(value: string): string =
  result = value
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&#39;")

proc ms(value: int): string =
  $value & "ms"

proc pct(value: float): string =
  value.formatFloat(ffDecimal, 1) & "%"

proc percentChange(beforeMs, afterMs: int): string =
  if beforeMs <= 0:
    return "n/a"
  let value = (beforeMs - afterMs).float / beforeMs.float * 100.0
  value.pct()

proc share(part, total: int): string =
  if total <= 0:
    return "0.0%"
  (part.float / total.float * 100.0).pct()

proc ratio(numerator, denominator: int): string =
  if denominator <= 0:
    return "n/a"
  (numerator.float / denominator.float).formatFloat(ffDecimal, 2)

proc factor(numerator, denominator: int): float =
  if denominator <= 0:
    return 0.0
  numerator.float / denominator.float

proc totalWorkMs(outcome: CaptainOutcome): int =
  for item in outcome.run.timeline:
    result.inc item.durationMs

proc totalWaitMs(outcome: CaptainOutcome): int =
  for item in outcome.survey.waitInsights:
    result.inc item.totalWaitMs

proc runByNode(outcome: CaptainOutcome): Table[string, NodeRun] =
  for item in outcome.run.timeline:
    result[item.nodeId] = item

proc nodeById(plan: CaptainPlan): Table[string, CaptainNode] =
  for item in plan.nodes:
    result[item.id] = item

proc degreeByNode(plan: CaptainPlan): Table[string, tuple[fanIn, fanOut: int]] =
  for item in plan.nodes:
    result[item.id] = (0, 0)
  for edge in plan.edges:
    if result.hasKey(edge.fromNode):
      result[edge.fromNode].fanOut.inc
    if result.hasKey(edge.toNode):
      result[edge.toNode].fanIn.inc

proc isCritical(outcome: CaptainOutcome; nodeId: string): bool =
  nodeId in outcome.analysis.criticalPath

proc waitByEdge(outcome: CaptainOutcome): Table[string, CaptainWaitInsight] =
  for item in outcome.survey.waitInsights:
    result[item.edgeId] = item

proc improvementImpactScore(item: CaptainParallelismOpportunity;
    totalWork, criticalPathMs: int): float =
  var score = item.score
  if totalWork > 0:
    score += item.observedDurationMs.float / totalWork.float * 100.0
  if criticalPathMs > 0 and item.onCriticalPath:
    score += item.observedDurationMs.float / criticalPathMs.float * 100.0
  score

proc sortedTimeline(outcome: CaptainOutcome): seq[NodeRun] =
  result = outcome.run.timeline
  result.sort(proc (a, b: NodeRun): int = cmp(b.durationMs, a.durationMs))

proc sortedWaits(outcome: CaptainOutcome): seq[CaptainWaitInsight] =
  result = outcome.survey.waitInsights
  result.sort(proc (a, b: CaptainWaitInsight): int =
    cmp(b.totalWaitMs, a.totalWaitMs))

proc sortedOpportunities(outcome: CaptainOutcome): seq[CaptainParallelismOpportunity] =
  result = outcome.survey.parallelismOpportunities
  result.sort(proc (a, b: CaptainParallelismOpportunity): int =
    cmp(improvementImpactScore(b, outcome.totalWorkMs(), outcome.analysis.criticalPathMs),
        improvementImpactScore(a, outcome.totalWorkMs(), outcome.analysis.criticalPathMs)))

proc topWait(insights: seq[CaptainWaitInsight]): CaptainWaitInsight =
  if insights.len > 0:
    return insights[0]

proc topParallelism(opportunities: seq[CaptainParallelismOpportunity]):
    CaptainParallelismOpportunity =
  if opportunities.len > 0:
    return opportunities[0]

proc addExecutiveSummary(result: var string; comparison: VariantComparison;
    selected: CaptainOutcome) =
  let baselineMs = comparison.baseline.analysis.criticalPathMs
  let candidateMs = comparison.candidate.analysis.criticalPathMs
  let gainMs = baselineMs - candidateMs
  result.add("## Executive summary\n\n")
  result.add("- Selected variant `" & selected.plan.variant & "` because it ")
  if gainMs > 0:
    result.add("shortened the critical path by `" & $gainMs & "ms` (`" &
      percentChange(baselineMs, candidateMs) & "`).\n")
  elif gainMs < 0:
    result.add("increased the critical path by `" & $(-gainMs) & "ms`; review before rollout.\n")
  else:
    result.add("matched the baseline critical path duration.\n")
  result.add("- Primary bottleneck: `" & selected.analysis.slowestNode &
    "` on `" & selected.analysis.criticalPath.joinPath() & "`.\n")
  result.add("- Total observed work is `" & selected.totalWorkMs().ms() &
    "` across `" & $selected.run.timeline.len & "` nodes; concurrency factor is `" &
    ratio(selected.totalWorkMs(), selected.run.totalMs) & "x`.\n")
  if selected.survey.waitInsights.len > 0:
    let wait = selected.survey.waitInsights.topWait()
    result.add("- Main handoff delay: `" & wait.edgeId & "` waited `" &
      $wait.totalWaitMs & "ms`.\n")
  else:
    result.add("- No observed handoff delay was reported.\n")
  if comparison.regressions.len > 0:
    result.add("- Trade-off: " & comparison.regressions[0] & ".\n")
  elif comparison.improvements.len > 0:
    result.add("- Additional observed change: " & comparison.improvements[0] & ".\n")
  else:
    result.add("- No additional observed work metric change was reported.\n")
  result.add("\n")

proc addKpiDashboard(result: var string; comparison: VariantComparison;
    selected: CaptainOutcome) =
  let baselineWork = comparison.baseline.totalWorkMs()
  let candidateWork = comparison.candidate.totalWorkMs()
  let selectedWork = selected.totalWorkMs()
  let selectedWait = selected.totalWaitMs()
  result.add("## KPI dashboard\n\n")
  result.add("| Metric | Baseline `" & comparison.baseline.plan.variant &
    "` | Candidate `" & comparison.candidate.plan.variant & "` | Selected `" &
    selected.plan.variant & "` | Delta | Meaning |\n")
  result.add("| --- | ---: | ---: | ---: | ---: | --- |\n")
  result.add("| Critical path | " & comparison.baseline.analysis.criticalPathMs.ms() &
    " | " & comparison.candidate.analysis.criticalPathMs.ms() & " | " &
    selected.analysis.criticalPathMs.ms() & " | " & comparison.deltaMs.ms() &
    " | Minimum end-to-end duration if the graph structure is unchanged. |\n")
  result.add("| Total observed work | " & baselineWork.ms() & " | " &
    candidateWork.ms() & " | " & selectedWork.ms() & " | " &
    (candidateWork - baselineWork).ms() &
    " | Sum of node durations; highlights added or removed work. |\n")
  result.add("| Elapsed run time | " & comparison.baseline.run.totalMs.ms() & " | " &
    comparison.candidate.run.totalMs.ms() & " | " & selected.run.totalMs.ms() &
    " | " & (comparison.candidate.run.totalMs -
    comparison.baseline.run.totalMs).ms() &
    " | Simulated wall-clock time observed by the runner. |\n")
  result.add("| Concurrency factor | " &
    ratio(baselineWork, comparison.baseline.run.totalMs) & "x | " &
    ratio(candidateWork, comparison.candidate.run.totalMs) & "x | " &
    ratio(selectedWork, selected.run.totalMs) &
    "x | n/a | Total work divided by elapsed time; higher means more parallel work. |\n")
  result.add("| Critical-path share | " &
    share(comparison.baseline.analysis.criticalPathMs, baselineWork) & " | " &
    share(comparison.candidate.analysis.criticalPathMs, candidateWork) & " | " &
    share(selected.analysis.criticalPathMs, selectedWork) &
    " | n/a | How much total work lies on the limiting path. |\n")
  result.add("| Observed wait | " & comparison.baseline.totalWaitMs().ms() & " | " &
    comparison.candidate.totalWaitMs().ms() & " | " & selectedWait.ms() &
    " | " & (comparison.candidate.totalWaitMs() -
    comparison.baseline.totalWaitMs()).ms() &
    " | Queueing or dependency handoff delay detected on edges. |\n")
  result.add("| Failed nodes | " & $comparison.baseline.analysis.failedNodes.len &
    " | " & $comparison.candidate.analysis.failedNodes.len & " | " &
    $selected.analysis.failedNodes.len & " | " &
    $(comparison.candidate.analysis.failedNodes.len -
      comparison.baseline.analysis.failedNodes.len) &
    " | Reliability signal before optimizing throughput. |\n")
  result.add("| Retries | " & $comparison.baseline.analysis.retryCount & " | " &
    $comparison.candidate.analysis.retryCount & " | " &
    $selected.analysis.retryCount & " | " &
    $(comparison.candidate.analysis.retryCount -
      comparison.baseline.analysis.retryCount) &
    " | Wasted work and instability indicator. |\n\n")

proc addFlowHealth(result: var string; selected: CaptainOutcome) =
  let scored = selected.health()
  result.add("## Flow health\n\n")
  result.add("| Metric | Value |\n")
  result.add("| --- | ---: |\n")
  result.add("| Score | `" & scored.score.formatFloat(ffDecimal, 1) & "` |\n")
  result.add("| Grade | `" & scored.grade & "` |\n")
  result.add("| Success rate | `" & (scored.successRate * 100.0).pct() & "` |\n")
  result.add("| Failure rate | `" & (scored.failureRate * 100.0).pct() & "` |\n")
  result.add("| Retry rate | `" & scored.retryRate.formatFloat(ffDecimal, 2) & "` |\n")
  result.add("| Wait share | `" & (scored.waitShare * 100.0).pct() & "` |\n")
  result.add("| Critical-path share | `" &
    (scored.criticalPathShare * 100.0).pct() & "` |\n")
  result.add("| Concurrency factor | `" &
    scored.concurrencyFactor.formatFloat(ffDecimal, 2) & "x` |\n\n")
  result.add("Health reasons:\n")
  for item in scored.reasons:
    result.add("- " & item & "\n")
  result.add("\n")

proc addDecisionRecord(result: var string; comparison: VariantComparison;
    selected: CaptainOutcome) =
  let baseline = comparison.baseline
  let candidate = comparison.candidate
  let criticalGain = baseline.analysis.criticalPathMs - candidate.analysis.criticalPathMs
  let workDelta = candidate.totalWorkMs() - baseline.totalWorkMs()
  let waitDelta = candidate.totalWaitMs() - baseline.totalWaitMs()
  let reliabilityOk = selected.analysis.failedNodes.len == 0 and
    selected.analysis.retryCount == 0
  let rollout =
    if comparison.betterVariant == "tie": "hold"
    elif selected.analysis.failedNodes.len > 0: "block"
    elif criticalGain > 0 and reliabilityOk: "candidate"
    else: "review"

  result.add("## Decision record\n\n")
  result.add("| Item | Value |\n")
  result.add("| --- | --- |\n")
  result.add("| Recommended decision | `" & rollout & "` |\n")
  result.add("| Selected variant | `" & selected.plan.variant & "` |\n")
  result.add("| Main reason | `" & comparison.summary.cell() & "` |\n")
  result.add("| Critical-path change | `" & criticalGain.ms() & "` (`" &
    percentChange(baseline.analysis.criticalPathMs,
      candidate.analysis.criticalPathMs) & "`) |\n")
  result.add("| Total-work change | `" & workDelta.ms() & "` |\n")
  result.add("| Handoff-wait change | `" & waitDelta.ms() & "` |\n")
  result.add("| Reliability gate | `" & (if reliabilityOk: "pass" else: "fail") & "` |\n")
  result.add("| Rollout condition | `critical path improves, failures stay at zero, and total-work increase is understood` |\n\n")

proc addVariantScorecard(result: var string; comparison: VariantComparison) =
  let baseline = comparison.baseline
  let candidate = comparison.candidate
  let baselineWork = baseline.totalWorkMs()
  let candidateWork = candidate.totalWorkMs()
  let baselineWait = baseline.totalWaitMs()
  let candidateWait = candidate.totalWaitMs()
  let baselineConcurrency = factor(baselineWork, baseline.run.totalMs)
  let candidateConcurrency = factor(candidateWork, candidate.run.totalMs)

  result.add("## Variant scorecard\n\n")
  result.add("| Dimension | Baseline `" & baseline.plan.variant & "` | Candidate `" &
    candidate.plan.variant & "` | Better | Readout |\n")
  result.add("| --- | ---: | ---: | --- | --- |\n")
  result.add("| Critical path | " & baseline.analysis.criticalPathMs.ms() & " | " &
    candidate.analysis.criticalPathMs.ms() & " | `" &
    (if candidate.analysis.criticalPathMs < baseline.analysis.criticalPathMs:
      candidate.plan.variant elif candidate.analysis.criticalPathMs >
      baseline.analysis.criticalPathMs: baseline.plan.variant else: "tie") &
    "` | End-to-end limiter. |\n")
  result.add("| Total observed work | " & baselineWork.ms() & " | " &
    candidateWork.ms() & " | `" &
    (if candidateWork < baselineWork: candidate.plan.variant
     elif candidateWork > baselineWork: baseline.plan.variant else: "tie") &
    "` | Lower is less total work. |\n")
  result.add("| Handoff wait | " & baselineWait.ms() & " | " &
    candidateWait.ms() & " | `" &
    (if candidateWait < baselineWait: candidate.plan.variant
     elif candidateWait > baselineWait: baseline.plan.variant else: "tie") &
    "` | Lower means less idle handoff time. |\n")
  result.add("| Concurrency factor | " &
    ratio(baselineWork, baseline.run.totalMs) & "x | " &
    ratio(candidateWork, candidate.run.totalMs) & "x | `" &
    (if candidateConcurrency > baselineConcurrency: candidate.plan.variant
     elif candidateConcurrency < baselineConcurrency: baseline.plan.variant
     else: "tie") & "` | Higher means more useful overlap. |\n")
  result.add("| Failed nodes | " & $baseline.analysis.failedNodes.len & " | " &
    $candidate.analysis.failedNodes.len & " | `" &
    (if candidate.analysis.failedNodes.len < baseline.analysis.failedNodes.len:
      candidate.plan.variant elif candidate.analysis.failedNodes.len >
      baseline.analysis.failedNodes.len: baseline.plan.variant else: "tie") &
    "` | Failures block adoption. |\n")
  result.add("| Retries | " & $baseline.analysis.retryCount & " | " &
    $candidate.analysis.retryCount & " | `" &
    (if candidate.analysis.retryCount < baseline.analysis.retryCount:
      candidate.plan.variant elif candidate.analysis.retryCount >
      baseline.analysis.retryCount: baseline.plan.variant else: "tie") &
    "` | Lower is more stable. |\n\n")

proc addOptimizationBacklog(result: var string; selected: CaptainOutcome) =
  result.add("## Optimization backlog\n\n")
  result.add("| Priority | Work item | Why it matters | Validation metric | Acceptance condition |\n")
  result.add("| ---: | --- | --- | --- | --- |\n")
  var priority = 1
  for item in selected.sortedOpportunities():
    if priority > 5:
      break
    result.add("| " & $priority & " | Split or parallelize `" & item.nodeId &
      "` | `" & item.observedDurationMs.ms() & "` and `" &
      share(item.observedDurationMs, selected.totalWorkMs()) &
      "` of total work; critical=`" & item.onCriticalPath.boolText() &
      "` | critical path, total observed work, concurrency factor | Critical path improves without increasing failures or retries. |\n")
    priority.inc
  for item in selected.sortedWaits():
    if priority > 7:
      break
    result.add("| " & $priority & " | Reduce handoff wait on `" & item.edgeId &
      "` | `" & item.totalWaitMs.ms() & "` total wait, `" &
      item.averageWaitMs.formatFloat(ffDecimal, 1) &
      "ms` average | wait time and downstream start time | Wait decreases and selected critical path does not move to a worse node. |\n")
    priority.inc
  if priority == 1:
    result.add("| 1 | Collect another measured run | No improvement candidate is strong enough from one run. | sample count and metric density | At least two comparable runs are available. |\n")
  result.add("\n")

proc addDataQuality(result: var string; comparison: VariantComparison;
    selected: CaptainOutcome) =
  let integrated = comparison.summarizeToolkitIntegration()
  let sampleCount = 1
  let metricDensity = integrated.logbookMetricDensity
  let timingCoverage = integrated.logbookTimingCoverage
  let hasMeasuredMetrics = metricDensity > 0.0
  result.add("## Data quality\n\n")
  result.add("| Check | Value | Quality | Impact |\n")
  result.add("| --- | ---: | --- | --- |\n")
  result.add("| Comparable runs | " & $sampleCount &
    " | `" & (if sampleCount >= 3: "strong" else: "limited") &
    "` | More runs improve confidence in the selected variant. |\n")
  result.add("| Timeline events | " & $selected.run.timeline.len &
    " | `" & (if selected.run.timeline.len == selected.plan.nodes.len:
      "complete" else: "partial") & "` | Missing node events weaken bottleneck analysis. |\n")
  result.add("| Timing coverage | " & timingCoverage.formatFloat(ffDecimal, 1) &
    "% | `" & (if timingCoverage >= 95.0: "strong" else: "limited") &
    "` | Duration-based recommendations depend on timing coverage. |\n")
  result.add("| Metric density | " & metricDensity.formatFloat(ffDecimal, 2) &
    " | `" & (if hasMeasuredMetrics: "present" else: "low") &
    "` | Domain metrics such as rows, bytes, CPU, or memory make root-cause analysis stronger. |\n")
  result.add("| Survey recommendations | " &
    $selected.survey.recommendations.len & " | `" &
    (if selected.survey.recommendations.len > 0: "present" else: "empty") &
    "` | Surveyor recommendations provide secondary evidence. |\n\n")

proc addRolloutChecklist(result: var string; selected: CaptainOutcome) =
  result.add("## Rollout checklist\n\n")
  result.add("| Gate | Current signal | Required before rollout |\n")
  result.add("| --- | --- | --- |\n")
  result.add("| Reliability | `" & $selected.analysis.failedNodes.len &
    "` failed nodes, `" & $selected.analysis.retryCount &
    "` retries | No unexplained failures or retry spikes. |\n")
  result.add("| Bottleneck movement | Slowest node is `" &
    selected.analysis.slowestNode & "` | Confirm the bottleneck moved in the expected direction. |\n")
  result.add("| Handoff delay | `" & selected.totalWaitMs().ms() &
    "` total wait | Wait increase must be accepted or reduced. |\n")
  result.add("| Measurement confidence | `" & $selected.run.timeline.len &
    "` timeline events | Run the same comparison again when decisions are high-impact. |\n")
  result.add("| Rollback path | selected variant `" & selected.plan.variant &
    "` | Keep the baseline graph available until candidate behavior is stable. |\n\n")

proc addNodeMetrics(result: var string; selected: CaptainOutcome) =
  let totalWork = selected.totalWorkMs()
  let nodes = selected.plan.nodeById()
  let degrees = selected.plan.degreeByNode()
  result.add("## Node metrics\n\n")
  if selected.run.timeline.len == 0:
    result.add("- No node execution data was available.\n\n")
    return
  result.add("| Rank | Node | Status | Planned | Actual | Variance | Work share | Critical | Fan-in | Fan-out | Retries |\n")
  result.add("| ---: | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |\n")
  var rank = 1
  for item in selected.sortedTimeline():
    let planned = nodes.getOrDefault(item.nodeId).plannedMs
    let degree = degrees.getOrDefault(item.nodeId, (0, 0))
    result.add("| " & $rank & " | `" & item.nodeId & "` | " &
      item.status.statusText() & " | " & planned.ms() & " | " &
      item.durationMs.ms() & " | " & (item.durationMs - planned).ms() &
      " | " & share(item.durationMs, totalWork) & " | " &
      selected.isCritical(item.nodeId).boolText() & " | " &
      $degree.fanIn & " | " & $degree.fanOut & " | " & $item.retries & " |\n")
    rank.inc
  result.add("\n")

proc addEdgeMetrics(result: var string; selected: CaptainOutcome) =
  let runs = selected.runByNode()
  let waits = selected.waitByEdge()
  result.add("## Edge metrics\n\n")
  if selected.plan.edges.len == 0:
    result.add("- No dependency edges were defined.\n\n")
    return
  result.add("| Edge | From | To | Kind | Wait-on | Source finish | Target start | Wait | Blocked | Status |\n")
  result.add("| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |\n")
  for edge in selected.plan.edges:
    let source = runs.getOrDefault(edge.fromNode)
    let target = runs.getOrDefault(edge.toNode)
    let wait = waits.getOrDefault(edge.id)
    let calculatedWait = max(0, target.startedMs - source.finishedMs)
    let waitMs = if wait.edgeId.len > 0: wait.totalWaitMs else: calculatedWait
    let status =
      if source.status == nsFailed or target.status == nsFailed: "failed"
      elif target.status == nsSkipped: "skipped"
      elif wait.blockedCount > 0: "blocked"
      elif waitMs > 0: "waiting"
      else: "satisfied"
    result.add("| `" & edge.id & "` | `" & edge.fromNode & "` | `" &
      edge.toNode & "` | " & edge.kind.kindText() & " | " & edge.waitOn.boolText() &
      " | " & source.finishedMs.ms() & " | " & target.startedMs.ms() &
      " | " & waitMs.ms() & " | " & $wait.blockedCount & " | " & status & " |\n")
  result.add("\n")

proc addImpactRanking(result: var string; selected: CaptainOutcome) =
  let totalWork = selected.totalWorkMs()
  result.add("## Improvement impact ranking\n\n")
  if selected.survey.parallelismOpportunities.len == 0 and
      selected.survey.waitInsights.len == 0 and
      selected.survey.failureImpacts.len == 0:
    result.add("- No quantified improvement candidate was detected.\n\n")
    return
  result.add("| Priority | Area | Target | Metric | Current value | Estimated impact | Evidence |\n")
  result.add("| ---: | --- | --- | --- | ---: | ---: | --- |\n")
  var priority = 1
  for item in selected.sortedOpportunities():
    let impact = improvementImpactScore(item, totalWork,
      selected.analysis.criticalPathMs)
    result.add("| " & $priority & " | Parallelism | `" & item.nodeId &
      "` | duration / work share | " & item.observedDurationMs.ms() & " / " &
      share(item.observedDurationMs, totalWork) & " | " &
      impact.formatFloat(ffDecimal, 1) & " | " & item.reason.cell() & " |\n")
    priority.inc
  for item in selected.sortedWaits():
    result.add("| " & $priority & " | Handoff wait | `" & item.edgeId &
      "` | total / average wait | " & item.totalWaitMs.ms() & " / " &
      item.averageWaitMs.formatFloat(ffDecimal, 1) & "ms | " &
      share(item.totalWaitMs, max(1, selected.run.totalMs)) & " | " &
      item.reason.cell() & " |\n")
    priority.inc
  for item in selected.survey.failureImpacts:
    result.add("| " & $priority & " | Reliability | `" & item.targetId &
      "` | failures / retries | " & $item.failureCount & " / " &
      $item.retryCount & " | " & item.score.formatFloat(ffDecimal, 1) &
      " | " & item.reason.cell() & " |\n")
    priority.inc
  result.add("\n")

proc addRiskRegister(result: var string; selected: CaptainOutcome) =
  result.add("## Operational risk register\n\n")
  result.add("| Risk | Signal | Severity | Suggested check |\n")
  result.add("| --- | --- | --- | --- |\n")
  if selected.analysis.failedNodes.len > 0:
    result.add("| Failed work | `" & selected.analysis.failedNodes.join("`, `") &
      "` | high | Fix failed nodes before rollout. |\n")
  if selected.analysis.retryCount > 0:
    result.add("| Retry waste | `" & $selected.analysis.retryCount &
      "` retries | medium | Check retry causes and backoff policy. |\n")
  if selected.totalWaitMs() > 0:
    result.add("| Handoff delay | `" & selected.totalWaitMs().ms() &
      "` total wait | medium | Inspect queues, dependency edges, and wait-on settings. |\n")
  if selected.survey.parallelismOpportunities.len > 0:
    let item = selected.survey.parallelismOpportunities.topParallelism()
    result.add("| Concentrated work | `" & item.nodeId & "` dominates improvement ranking | medium | Try a split-work variant and compare total work. |\n")
  if selected.analysis.failedNodes.len == 0 and selected.analysis.retryCount == 0 and
      selected.totalWaitMs() == 0 and selected.survey.parallelismOpportunities.len == 0:
    result.add("| No immediate operational risk | Current run has no failures, retries, waits, or split-work candidates. | low | Collect more runs before relying on this as stable. |\n")
  result.add("\n")

proc addImprovementPlan(result: var string; selected: CaptainOutcome) =
  result.add("## Improvement plan\n\n")
  result.add("| Priority | Target | Action | Expected effect | Risk |\n")
  result.add("| ---: | --- | --- | --- | --- |\n")
  if selected.survey.parallelismOpportunities.len > 0:
    let item = selected.survey.parallelismOpportunities.topParallelism()
    result.add("| 1 | `" & item.nodeId & "` | Split or parallelize the work unit. | Reduce critical-path pressure if the work can be divided. | More coordination and possible total-work increase. |\n")
  else:
    result.add("| 1 | Critical path | Review the slowest critical-path node manually. | Identify the first concrete optimization target. | Manual review may not find a safe split. |\n")
  if selected.survey.waitInsights.len > 0:
    let wait = selected.survey.waitInsights.topWait()
    result.add("| 2 | `" & wait.edgeId & "` | Reduce queueing or handoff delay. | Lower downstream idle time. | Over-optimizing a small wait may not improve end-to-end time. |\n")
  else:
    result.add("| 2 | Handoffs | Keep monitoring wait events. | Confirm that handoffs are not hiding latency. | Missing telemetry can hide real waits. |\n")
  if selected.survey.failureImpacts.len > 0:
    let impact = selected.survey.failureImpacts[0]
    result.add("| 3 | `" & impact.targetId & "` | Reduce failures and retries before throughput tuning. | Avoid wasted work and unstable timings. | Reliability work may delay speed work. |\n")
  else:
    result.add("| 3 | Reliability | Keep failure and retry tracking enabled. | Preserve confidence in timing analysis. | Low sample count can make the flow look healthier than it is. |\n")
  result.add("\n")

proc addTradeOffs(result: var string; comparison: VariantComparison) =
  result.add("## Trade-offs\n\n")
  result.add("- Critical-path delta: `" & $comparison.deltaMs & "ms`.\n")
  if comparison.surveySummary.len > 0:
    result.add("- Total-work view: " & comparison.surveySummary & ".\n")
  if comparison.improvements.len > 0:
    result.add("- Improvements:\n")
    for item in comparison.improvements:
      result.add("  - " & item & "\n")
  if comparison.regressions.len > 0:
    result.add("- Regressions:\n")
    for item in comparison.regressions:
      result.add("  - " & item & "\n")
  if comparison.improvements.len == 0 and comparison.regressions.len == 0:
    result.add("- No additional work metric movement was reported.\n")
  result.add("\n")

proc addExperimentCandidates(result: var string; selected: CaptainOutcome) =
  result.add("## Next experiment candidates\n\n")
  result.add("| Candidate | Change | Measurement |\n")
  result.add("| --- | --- | --- |\n")
  if selected.survey.parallelismOpportunities.len > 0:
    let item = selected.survey.parallelismOpportunities.topParallelism()
    result.add("| `C` | Split `" & item.nodeId & "` into smaller parallel nodes. | Compare critical path, total observed work, and handoff wait. |\n")
  else:
    result.add("| `C` | Add finer metrics around the slowest node. | Confirm whether the node can be split safely. |\n")
  if selected.survey.waitInsights.len > 0:
    let wait = selected.survey.waitInsights.topWait()
    result.add("| `D` | Change dependency or queueing around `" & wait.edgeId & "`. | Compare wait time and downstream start time. |\n")
  else:
    result.add("| `D` | Add edge wait telemetry. | Confirm that no hidden handoff delay exists. |\n")
  result.add("| `E` | Keep the current graph and collect another run. | Validate that this run is representative. |\n\n")

proc addEvidence(result: var string; comparison: VariantComparison;
    selected: CaptainOutcome) =
  result.add("## Evidence\n\n")
  result.add("- Baseline critical path: `" &
    $comparison.baseline.analysis.criticalPathMs & "ms`.\n")
  result.add("- Candidate critical path: `" &
    $comparison.candidate.analysis.criticalPathMs & "ms`.\n")
  result.add("- Selected critical path: `" &
    selected.analysis.criticalPath.joinPath() & "`.\n")
  result.add("- Timeline event count: `" & $selected.run.timeline.len & "`.\n")
  result.add("- FlowSurveyor recommendation count: `" &
    $selected.survey.recommendations.len & "`.\n\n")

proc addWaitInsights(result: var string; insights: seq[CaptainWaitInsight]) =
  result.add("## Wait insights\n\n")
  if insights.len == 0:
    result.add("- No observed wait or blocked handoff was detected.\n\n")
    return
  result.add("| Edge | From | To | Total wait | Average wait | Blocked | Reason |\n")
  result.add("| --- | --- | --- | ---: | ---: | ---: | --- |\n")
  for item in insights:
    result.add("| `" & item.edgeId & "` | `" & item.fromNode & "` | `" &
      item.toNode & "` | " & $item.totalWaitMs & "ms | " &
      $item.averageWaitMs & "ms | " & $item.blockedCount & " | " &
      item.reason & " |\n")
  result.add("\n")

proc addParallelism(result: var string;
    opportunities: seq[CaptainParallelismOpportunity]) =
  result.add("## Parallelism opportunities\n\n")
  if opportunities.len == 0:
    result.add("- No parallelism or split-work candidate was detected.\n\n")
    return
  result.add("| Node | Duration | Fan-in | Fan-out | Critical path | Score | Reason |\n")
  result.add("| --- | ---: | ---: | ---: | --- | ---: | --- |\n")
  for item in opportunities:
    result.add("| `" & item.nodeId & "` | " & $item.observedDurationMs &
      "ms | " & $item.fanIn & " | " & $item.fanOut & " | " &
      item.onCriticalPath.boolText() & " | " & $item.score & " | " &
      item.reason & " |\n")
  result.add("\n")

proc addFailureImpact(result: var string; impacts: seq[CaptainFailureImpact]) =
  result.add("## Failure and retry impact\n\n")
  if impacts.len == 0:
    result.add("- No failure or retry impact was detected.\n\n")
    return
  result.add("| Target | Kind | Failures | Retries | Failed duration | Retry duration | Score | Reason |\n")
  result.add("| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |\n")
  for item in impacts:
    result.add("| `" & item.targetId & "` | " & item.kind & " | " &
      $item.failureCount & " | " & $item.retryCount & " | " &
      $item.failedDurationMs & "ms | " & $item.retryDurationMs & "ms | " &
      $item.score & " | " & item.reason & " |\n")
  result.add("\n")

proc addSurveyorRecommendations(result: var string; insights: CaptainSurveyInsights) =
  result.add("## FlowSurveyor recommendations\n\n")
  if insights.recommendations.len == 0:
    result.add("- No FlowSurveyor recommendation was generated.\n\n")
    return
  for item in insights.recommendations:
    result.add("- " & item & "\n")
  result.add("\n")

proc markdownReport*(comparison: VariantComparison): string =
  let selected = if comparison.betterVariant == comparison.candidate.plan.variant:
      comparison.candidate
    else:
      comparison.baseline

  result.add("# FlowCaptain Report\n\n")
  result.addExecutiveSummary(comparison, selected)
  result.addKpiDashboard(comparison, selected)
  result.addFlowHealth(selected)
  result.addDecisionRecord(comparison, selected)
  result.addVariantScorecard(comparison)
  result.addDataQuality(comparison, selected)

  result.add("## Overview\n\n")
  result.add("- Plan: `" & selected.plan.id & "`\n")
  result.add("- Selected variant: `" & selected.plan.variant & "`\n")
  result.add("- Status: `" & (if selected.run.ok: "ok" else: "failed") & "`\n")
  result.add("- Total simulated time: `" & $selected.run.totalMs & "ms`\n")
  result.add("- Critical path: `" & selected.analysis.criticalPath.joinPath() & "`\n")
  result.add("- Critical path time: `" & $selected.analysis.criticalPathMs & "ms`\n")
  result.add("- Slowest node: `" & selected.analysis.slowestNode & "` (`" &
             $selected.analysis.slowestNodeMs & "ms`)\n\n")

  result.add("## Flow diagram\n\n")
  result.add("```mermaid\n")
  result.add(selected.mermaid())
  result.add("```\n\n")

  result.add("## Structure diagram\n\n")
  result.add("```mermaid\n")
  result.add(selected.structureMermaid())
  result.add("```\n\n")

  result.add("## Timeline\n\n")
  result.add("| Node | Status | Start | Finish | Duration | Retries |\n")
  result.add("| --- | --- | ---: | ---: | ---: | ---: |\n")
  for item in selected.run.timeline:
    result.add("| `" & item.nodeId & "` | " & item.status.statusText() & " | " &
               $item.startedMs & "ms | " & $item.finishedMs & "ms | " &
               $item.durationMs & "ms | " & $item.retries & " |\n")
  result.add("\n")

  result.addNodeMetrics(selected)
  result.addEdgeMetrics(selected)
  result.addImpactRanking(selected)
  result.addRiskRegister(selected)

  result.add("## Bottlenecks\n\n")
  result.add("- Slowest node: `" & selected.analysis.slowestNode & "`\n")
  result.add("- Critical path: `" & selected.analysis.criticalPath.joinPath() & "`\n\n")

  result.addWaitInsights(selected.survey.waitInsights)
  result.addParallelism(selected.survey.parallelismOpportunities)
  result.addFailureImpact(selected.survey.failureImpacts)

  result.add("## Failures and retries\n\n")
  if selected.analysis.failedNodes.len == 0:
    result.add("- Failed nodes: none\n")
  else:
    result.add("- Failed nodes: `" & selected.analysis.failedNodes.join("`, `") & "`\n")
  result.add("- Retry count: `" & $selected.analysis.retryCount & "`\n\n")

  result.add("## Variant comparison\n\n")
  result.add("```mermaid\n")
  result.add(comparison.comparisonMermaid())
  result.add("```\n\n")
  result.add("- Baseline critical path: `" & $comparison.baseline.analysis.criticalPathMs & "ms`\n")
  result.add("- Candidate critical path: `" & $comparison.candidate.analysis.criticalPathMs & "ms`\n")
  result.add("- Result: " & comparison.summary & "\n\n")
  result.add("- FlowSurveyor summary: " & comparison.surveySummary & "\n")
  if comparison.improvements.len > 0:
    result.add("- Improvements:\n")
    for item in comparison.improvements:
      result.add("  - " & item & "\n")
  if comparison.regressions.len > 0:
    result.add("- Regressions:\n")
    for item in comparison.regressions:
      result.add("  - " & item & "\n")
  result.add("\n")

  result.add("## Recommendation\n\n")
  result.add(selected.analysis.recommendation & "\n\n")
  result.addImprovementPlan(selected)
  result.addOptimizationBacklog(selected)
  result.addTradeOffs(comparison)
  result.addExperimentCandidates(selected)
  result.addRolloutChecklist(selected)
  result.addEvidence(comparison, selected)
  result.addSurveyorRecommendations(selected.survey)

  let integrated = comparison.summarizeToolkitIntegration()
  result.add("## Toolkit integration\n\n")
  result.add("| Component | Integrated output |\n")
  result.add("| --- | ---: |\n")
  result.add("| FlowDependency nodes | " & $integrated.dependencyNodes & " |\n")
  result.add("| FlowDependency edges | " & $integrated.dependencyEdges & " |\n")
  result.add("| FlowDependency sources | " & $integrated.dependencySources & " |\n")
  result.add("| FlowDependency sinks | " & $integrated.dependencySinks & " |\n")
  result.add("| FlowDependency max fan-in | " & $integrated.dependencyMaxFanIn & " |\n")
  result.add("| FlowDependency max fan-out | " & $integrated.dependencyMaxFanOut & " |\n")
  result.add("| FlowDependency density | " &
    integrated.dependencyDensity.formatFloat(ffDecimal, 3) & " |\n")
  result.add("| FlowWorkRunner nodes | " & $integrated.workNodes & " |\n")
  result.add("| FlowWorkRunner edges | " & $integrated.workEdges & " |\n")
  result.add("| FlowWorkRunner batches | " & $integrated.workBatches & " |\n")
  result.add("| FlowWorkRunner max batch width | " &
    $integrated.workMaxBatchWidth & " |\n")
  result.add("| FlowWorkRunner parallelism factor | " &
    integrated.workParallelismFactor.formatFloat(ffDecimal, 2) & "x |\n")
  result.add("| FlowWorkRunner success rate | " &
    integrated.workSuccessRate.formatFloat(ffDecimal, 1) & "% |\n")
  result.add("| FlowLogbook events | " & $integrated.logbookEvents & " |\n")
  result.add("| FlowLogbook metric density | " &
    integrated.logbookMetricDensity.formatFloat(ffDecimal, 2) & " |\n")
  result.add("| FlowLogbook timing coverage | " &
    integrated.logbookTimingCoverage.formatFloat(ffDecimal, 1) & "% |\n")
  result.add("| FlowSurveyor recommendations | " &
    $integrated.surveyRecommendations & " |\n")
  result.add("| FlowGarage sections | " & $integrated.garageSections & " |\n")
  result.add("| FlowGarage artifacts | " & $integrated.garageArtifacts & " |\n\n")

  result.add("## Generated artifacts\n\n")
  result.add("- `captain-report.md`\n")
  result.add("- `captain-report.html`\n")
  result.add("- `flow.mmd`\n")
  result.add("- `structure.mmd`\n")
  result.add("- `comparison.mmd`\n")
  result.add("- `manifest.json`\n")

proc htmlReport*(comparison: VariantComparison): string =
  let selected = if comparison.betterVariant == comparison.candidate.plan.variant:
      comparison.candidate
    else:
      comparison.baseline
  let degrees = selected.plan.degreeByNode()
  let waits = selected.waitByEdge()
  let runRows = selected.runByNode()
  let scored = selected.health()

  result.add("<!doctype html>\n<html lang=\"en\">\n<head>\n")
  result.add("<meta charset=\"utf-8\">\n")
  result.add("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n")
  result.add("<title>FlowCaptain Report - " & selected.plan.id.html() & "</title>\n")
  result.add("<style>\n")
  result.add("body{font-family:system-ui,-apple-system,Segoe UI,sans-serif;margin:0;background:#f6f8fa;color:#1f2328;line-height:1.45}main{max-width:1180px;margin:0 auto;padding:24px}section{background:#fff;border:1px solid #d0d7de;border-radius:8px;padding:18px;margin:16px 0}h1,h2{margin:0 0 12px}.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px}.kpi{border:1px solid #d8dee4;border-radius:6px;padding:10px;background:#fbfcfd}.kpi b{display:block;font-size:20px}.batches{display:flex;gap:12px;overflow:auto;padding-bottom:8px}.batch{min-width:190px;border:1px solid #d0d7de;border-radius:6px;background:#fbfcfd;padding:10px}.node{border:1px solid #8c959f;border-left:4px solid #0969da;border-radius:6px;background:#fff;margin:8px 0;padding:8px}.node.critical{border-left-color:#1a7f37}.node.failed{border-left-color:#cf222e}.node.skipped{border-left-color:#bf8700}.arrow{color:#57606a;text-align:center;font-weight:700;align-self:center}table{width:100%;border-collapse:collapse;font-size:14px}th,td{border:1px solid #d0d7de;padding:7px;text-align:left}th{background:#f6f8fa}.muted{color:#57606a}.badge{display:inline-block;border:1px solid #d0d7de;border-radius:999px;padding:1px 7px;background:#f6f8fa;font-size:12px}</style>\n")
  result.add("</head>\n<body>\n<main>\n")
  result.add("<h1>FlowCaptain Report</h1>\n")
  result.add("<p class=\"muted\">Plan <b>" & selected.plan.id.html() & "</b>, variant <b>" &
    selected.plan.variant.html() & "</b></p>\n")

  result.add("<section><h2>Summary</h2><div class=\"kpis\">")
  result.add("<div class=\"kpi\">Status<b>" & (if selected.run.ok: "ok" else: "failed") & "</b></div>")
  result.add("<div class=\"kpi\">Elapsed<b>" & selected.run.totalMs.ms().html() & "</b></div>")
  result.add("<div class=\"kpi\">Critical path<b>" & selected.analysis.criticalPathMs.ms().html() & "</b></div>")
  result.add("<div class=\"kpi\">Total work<b>" & selected.totalWorkMs().ms().html() & "</b></div>")
  result.add("<div class=\"kpi\">Health<b>" &
    scored.score.formatFloat(ffDecimal, 1).html() & " / " &
    scored.grade.html() & "</b></div>")
  result.add("<div class=\"kpi\">Retries<b>" & $selected.analysis.retryCount & "</b></div>")
  result.add("<div class=\"kpi\">Selected variant<b>" & selected.plan.variant.html() & "</b></div>")
  result.add("</div><p>" & comparison.summary.html() & "</p></section>\n")

  result.add("<section><h2>Execution Flow</h2><div class=\"batches\">")
  for index, batch in selected.dryRun.batches:
    if index > 0:
      result.add("<div class=\"arrow\">&rarr;</div>")
    result.add("<div class=\"batch\"><b>Batch " & $(index + 1) & "</b>")
    for nodeId in batch:
      let run = runRows.getOrDefault(nodeId)
      let cls =
        if run.status == nsFailed: "node failed"
        elif run.status == nsSkipped: "node skipped"
        elif selected.isCritical(nodeId): "node critical"
        else: "node"
      result.add("<div class=\"" & cls & "\"><b>" & nodeId.html() & "</b><br>")
      result.add("<span class=\"muted\">" & selected.plan.nodeById().getOrDefault(nodeId).title.html() & "</span><br>")
      result.add("<span class=\"badge\">" & $run.status & "</span> ")
      result.add("<span class=\"badge\">" & run.durationMs.ms().html() & "</span></div>")
    result.add("</div>")
  result.add("</div></section>\n")

  result.add("<section><h2>Nodes</h2><table><thead><tr><th>Node</th><th>Title</th><th>Status</th><th>Duration</th><th>Retries</th><th>Fan-in</th><th>Fan-out</th><th>Critical</th></tr></thead><tbody>")
  for item in selected.plan.nodes:
    let run = runRows.getOrDefault(item.id)
    let degree = degrees.getOrDefault(item.id)
    result.add("<tr><td><code>" & item.id.html() & "</code></td><td>" & item.title.html() &
      "</td><td>" & ($run.status).html() & "</td><td>" & run.durationMs.ms().html() &
      "</td><td>" & $run.retries & "</td><td>" & $degree.fanIn & "</td><td>" &
      $degree.fanOut & "</td><td>" & (if selected.isCritical(item.id): "yes" else: "no") &
      "</td></tr>")
  result.add("</tbody></table></section>\n")

  result.add("<section><h2>Arrows</h2><table><thead><tr><th>Arrow</th><th>From</th><th>To</th><th>Kind</th><th>Wait on</th><th>Observed wait</th></tr></thead><tbody>")
  for edge in selected.plan.edges:
    let wait = waits.getOrDefault(edge.id)
    result.add("<tr><td><code>" & edge.id.html() & "</code></td><td><code>" &
      edge.fromNode.html() & "</code></td><td><code>" & edge.toNode.html() &
      "</code></td><td>" & edge.kind.kindText().html() & "</td><td>" &
      edge.waitOn.boolText() & "</td><td>" & wait.totalWaitMs.ms().html() & "</td></tr>")
  result.add("</tbody></table></section>\n")

  result.add("<section><h2>Recommendation</h2><p>" &
    selected.analysis.recommendation.html() & "</p></section>\n")
  result.add("</main>\n</body>\n</html>\n")

proc artifacts*(comparison: VariantComparison): CaptainArtifacts =
  let report = markdownReport(comparison)
  let reportHtml = htmlReport(comparison)
  let selected = if comparison.betterVariant == comparison.candidate.plan.variant:
      comparison.candidate
    else:
      comparison.baseline
  let flow = selected.mermaid()
  let structure = selected.structureMermaid()
  let compareGraph = comparison.comparisonMermaid()
  let manifest = manifestJson(report, reportHtml, flow, structure, compareGraph)
  CaptainArtifacts(reportMarkdown: report, reportHtml: reportHtml, flowMermaid: flow,
                   structureMermaid: structure,
                   comparisonMermaid: compareGraph, manifestJson: manifest)
