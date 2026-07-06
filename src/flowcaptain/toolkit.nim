import flowdependency as fd
import flowgarage as fg
import flowlogbook as fl
import flowworkrunner as fw

import ./types as cap

proc depWaitPolicy(edge: cap.CaptainEdge): fd.WaitPolicy =
  if edge.waitOn and edge.kind == cap.ekRequired:
    fd.wpRequired
  else:
    fd.wpOptional

proc toDependencyGraph*(plan: cap.CaptainPlan): fd.FlowGraph =
  result = fd.initFlowGraph(plan.id, variantId = plan.variant)
  for item in plan.nodes:
    result.nodes.add(fd.flowNode(item.id, item.title,
      kind = fd.nkTask,
      variantId = plan.variant))
  for item in plan.edges:
    result.edges.add(fd.flowEdge(item.id, item.fromNode, item.toNode,
      waitPolicy = item.depWaitPolicy(),
      required = item.kind == cap.ekRequired,
      durationMillis = Natural(0),
      variantId = plan.variant))

proc toWorkGraph*(plan: cap.CaptainPlan): fw.WorkGraph =
  result = fw.initWorkGraph(plan.id, variantId = plan.variant)
  for item in plan.nodes:
    result.nodes.add(fw.workNode(item.id, item.title,
      variantId = plan.variant))
  for item in plan.edges:
    result.edges.add(fw.workEdge(item.id, item.fromNode, item.toNode,
      waitOn = item.waitOn))

proc workStatus(status: cap.NodeStatus): fw.WorkStatus =
  case status
  of cap.nsPending: fw.wsPending
  of cap.nsSucceeded: fw.wsSucceeded
  of cap.nsFailed: fw.wsFailed
  of cap.nsSkipped: fw.wsSkipped

proc toWorkRunReport*(outcome: cap.CaptainOutcome): fw.WorkRunReport =
  result = fw.WorkRunReport(
    schemaVersion: fw.ReportSchemaVersion,
    flowId: outcome.plan.id,
    runId: outcome.run.planId & ":" & outcome.plan.variant,
    variantId: outcome.plan.variant,
    status: if outcome.run.ok: fw.wsSucceeded else: fw.wsFailed,
    errors: outcome.run.errors
  )
  for index, batch in outcome.dryRun.batches:
    result.batches.add(fw.ReadyBatch(index: Natural(index), nodeIds: batch))
  for item in outcome.run.timeline:
    var metrics: seq[fw.KeyValue] = @[]
    if item.retries > 0:
      metrics.add(fw.kv("retries", $item.retries))
    result.results.add(fw.WorkTaskResult(
      nodeId: item.nodeId,
      status: item.status.workStatus(),
      durationMillis: Natural(item.durationMs),
      message: item.message,
      metrics: metrics
    ))

proc logStatus(status: cap.NodeStatus): fl.RunStatus =
  case status
  of cap.nsPending: fl.rsPending
  of cap.nsSucceeded: fl.rsCompleted
  of cap.nsFailed: fl.rsFailed
  of cap.nsSkipped: fl.rsSkipped

proc toLogbookEvents*(outcome: cap.CaptainOutcome): seq[fl.FlowEvent] =
  for item in outcome.run.timeline:
    var metrics: seq[fl.KeyValue] = @[]
    if item.retries > 0:
      metrics.add(fl.kv("retries", $item.retries))
    result.add(fl.nodeEvent(
      "node:" & outcome.plan.variant & ":" & item.nodeId,
      "flowcaptain",
      outcome.plan.id,
      outcome.run.planId & ":" & outcome.plan.variant,
      item.nodeId,
      fl.fekNodeFinished,
      variantId = outcome.plan.variant,
      status = item.status.logStatus(),
      durationMillis = Natural(item.durationMs),
      metrics = metrics,
      message = item.message
    ))

proc toGarageBundle*(comparison: cap.VariantComparison;
    output: cap.CaptainArtifacts): fg.GarageBundle =
  result = fg.initGarageBundle(comparison.candidate.plan.id,
    "FlowCaptain Report",
    summary = comparison.summary)
  result.sections.add(fg.section("summary", "Summary", comparison.summary))
  if comparison.surveySummary.len > 0:
    result.sections.add(fg.section("survey", "FlowSurveyor Summary",
      comparison.surveySummary))
  result.artifacts.add(fg.artifact("captain-report", "Captain Report",
    kind = fg.akReport,
    mediaType = "text/markdown",
    content = output.reportMarkdown))
  result.artifacts.add(fg.artifact("flow-mermaid", "Flow Diagram",
    kind = fg.akReport,
    mediaType = "text/vnd.mermaid",
    content = output.flowMermaid))
  result.artifacts.add(fg.artifact("comparison-mermaid", "Variant Comparison",
    kind = fg.akReport,
    mediaType = "text/vnd.mermaid",
    content = output.comparisonMermaid))

type
  ToolkitIntegrationSummary* = object
    dependencyNodes*: int
    dependencyEdges*: int
    dependencySources*: int
    dependencySinks*: int
    dependencyMaxFanIn*: int
    dependencyMaxFanOut*: int
    dependencyDensity*: float
    workNodes*: int
    workEdges*: int
    workBatches*: int
    workMaxBatchWidth*: int
    workParallelismFactor*: float
    workSuccessRate*: float
    logbookEvents*: int
    logbookMetricDensity*: float
    logbookTimingCoverage*: float
    garageArtifacts*: int
    garageSections*: int
    surveyRecommendations*: int

proc summarizeToolkitIntegration*(comparison: cap.VariantComparison):
    ToolkitIntegrationSummary =
  let dep = comparison.candidate.plan.toDependencyGraph()
  let work = comparison.candidate.plan.toWorkGraph()
  let depMetrics = dep.graphMetrics()
  let workMetrics = comparison.candidate.toWorkRunReport().workRunMetrics()
  let events = comparison.candidate.toLogbookEvents()
  let logMetrics = events.eventMetrics()
  ToolkitIntegrationSummary(
    dependencyNodes: dep.nodes.len,
    dependencyEdges: dep.edges.len,
    dependencySources: int(depMetrics.sourceCount),
    dependencySinks: int(depMetrics.sinkCount),
    dependencyMaxFanIn: int(depMetrics.maxFanIn),
    dependencyMaxFanOut: int(depMetrics.maxFanOut),
    dependencyDensity: depMetrics.density,
    workNodes: work.nodes.len,
    workEdges: work.edges.len,
    workBatches: int(workMetrics.batchCount),
    workMaxBatchWidth: int(workMetrics.maxBatchWidth),
    workParallelismFactor: workMetrics.parallelismFactor,
    workSuccessRate: workMetrics.successRate,
    logbookEvents: events.len,
    logbookMetricDensity: logMetrics.metricDensity,
    logbookTimingCoverage: logMetrics.timingCoverage,
    garageArtifacts: 3,
    garageSections: (if comparison.surveySummary.len > 0: 2 else: 1),
    surveyRecommendations: comparison.candidate.survey.recommendations.len
  )
