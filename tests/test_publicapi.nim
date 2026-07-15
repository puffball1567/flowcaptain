import std/[json, os, sequtils, strutils, unittest]

import flowbrigade
import flowcaptain

proc samplePlan(variant = "A"): CaptainPlan =
  result = initCaptainPlan("billing", "Billing", variant = variant)
  result.nodes.add(node("load-users", "Load users", plannedMs = 120))
  result.nodes.add(node("calculate", "Calculate", plannedMs = 850, retries = 1))
  result.nodes.add(node("render", "Render", plannedMs = 410))
  result.nodes.add(node("send-mail", "Send mail", plannedMs = 90))
  result.edges.add(edge("load-calculate", "load-users", "calculate"))
  result.edges.add(edge("load-render", "load-users", "render"))
  result.edges.add(edge("calculate-mail", "calculate", "send-mail"))
  result.edges.add(edge("render-mail", "render", "send-mail"))

proc fasterPlan(): CaptainPlan =
  result = initCaptainPlan("billing", "Billing", variant = "B")
  result.nodes.add(node("load-users", "Load users", plannedMs = 120))
  result.nodes.add(node("calculate-a", "Calculate A", plannedMs = 430))
  result.nodes.add(node("calculate-b", "Calculate B", plannedMs = 410))
  result.nodes.add(node("render", "Render", plannedMs = 410))
  result.nodes.add(node("send-mail", "Send mail", plannedMs = 90))
  result.edges.add(edge("load-a", "load-users", "calculate-a"))
  result.edges.add(edge("load-b", "load-users", "calculate-b"))
  result.edges.add(edge("load-render", "load-users", "render"))
  result.edges.add(edge("a-mail", "calculate-a", "send-mail"))
  result.edges.add(edge("b-mail", "calculate-b", "send-mail"))
  result.edges.add(edge("render-mail", "render", "send-mail"))

proc cyclicPlan(): CaptainPlan =
  result = initCaptainPlan("cycle", "Cycle")
  result.nodes.add(node("a", "A", plannedMs = 1))
  result.nodes.add(node("b", "B", plannedMs = 1))
  result.edges.add(edge("a-b", "a", "b"))
  result.edges.add(edge("b-a", "b", "a"))

proc invalidReferencePlan(): CaptainPlan =
  result = initCaptainPlan("broken", "Broken")
  result.nodes.add(node("a", "A", plannedMs = 1))
  result.edges.add(edge("a-missing", "a", "missing"))

proc failingPlan(): CaptainPlan =
  result = samplePlan()
  result.nodes[1] = node("calculate", "Calculate", plannedMs = 850,
    fail = true, retries = 2)

proc sampleEvents(): seq[CaptainAdapterEvent] =
  @[
    adapterEvent("runStarted", "billing", "run-1", variantId = "A",
      timestampMs = 1000),
    adapterEvent("nodeStarted", "billing", "run-1", variantId = "A",
      nodeId = "load-users", timestampMs = 1000),
    adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
      nodeId = "load-users", timestampMs = 1120, durationMs = 120,
      status = nsSucceeded),
    adapterEvent("nodeStarted", "billing", "run-1", variantId = "A",
      nodeId = "calculate", timestampMs = 1120),
    adapterEvent("nodeStarted", "billing", "run-1", variantId = "A",
      nodeId = "render", timestampMs = 1120),
    adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
      nodeId = "render", timestampMs = 1530, durationMs = 410,
      status = nsSucceeded),
    adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
      nodeId = "calculate", timestampMs = 1970, durationMs = 850,
      status = nsSucceeded, retryCount = 1),
    adapterEvent("edgeWaitObserved", "billing", "run-1", variantId = "A",
      edgeId = "render-mail", timestampMs = 1970, durationMs = 440,
      status = nsSucceeded, message = "render finished before calculate"),
    adapterEvent("nodeStarted", "billing", "run-1", variantId = "A",
      nodeId = "send-mail", timestampMs = 1970),
    adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
      nodeId = "send-mail", timestampMs = 2060, durationMs = 90,
      status = nsSucceeded),
    adapterEvent("runFinished", "billing", "run-1", variantId = "A",
      timestampMs = 2060, durationMs = 1060, status = nsSucceeded)
  ]

suite "public integration API":
  test "validates, normalizes, summarizes, and dry-runs plans":
    let plan = samplePlan()
    let loaded = loadPlanJson(savePlanJson(plan))
    check loaded.id == "billing"
    check validatePlan(loaded).ok
    check validatePlanJson(savePlanJson(loaded))["ok"].getBool()

    let normalized = initCaptainPlan(" billing-flow ", "Billing").normalizePlan()
    check normalized.id == "billing-flow"

    let dry = dryRunPlan(loaded)
    check dry.ok
    check dry.batches.len == 3
    let summary = graphSummary(loaded)
    check summary.sources == @["load-users"]
    check summary.sinks == @["send-mail"]
    check graphSummaryJson(loaded)["batches"].len == 3

  test "executes through the toolkit and exposes analysis, health, metrics, and diagrams":
    let baseline = samplePlan()
    let candidate = fasterPlan()
    let outcome = executePlan(baseline)
    check outcome.run.ok
    check outcome.analysis.criticalPathMs > 0
    check flowHealth(outcome).score > 0
    check flowDiagram(outcome).contains("flowchart LR")
    check structureDiagram(outcome).contains("classDiagram")
    check executePlanJson(savePlanJson(baseline))["analysis"]["criticalPathMs"].getInt() > 0

    let comparison = comparePlanVariants(baseline, candidate)
    check comparison.betterVariant == "B"
    check comparisonDiagram(comparison).contains("subgraph A")
    check metricEventsFor(comparison).len > 0
    check metricEventsJsonFor(comparison).len > 0
    check metricEventsJsonLinesFor(comparison).contains("criticalPathMs")
    check comparePlanVariantsJson(savePlanJson(baseline),
      savePlanJson(candidate))["betterVariant"].getStr() == "B"
    check diffPlanJson(savePlanJson(baseline),
      savePlanJson(candidate))["changes"].len > 0

  test "imports adapter JSONL and reaches full report generation":
    let plan = samplePlan()
    let events = sampleEvents()
    let jsonl = exportEventsJsonl(events)
    check importEventsJsonl(jsonl).len == events.len
    let contract = validateAdapterEventsContractJsonl(jsonl)
    check contract.ok
    check adapterContractJson(contract)["eventCount"].getInt() == events.len

    let outcome = analyzeAdapterEvents(plan, events)
    check outcome.run.ok
    check outcome.analysis.criticalPath == @[
      "load-users", "calculate", "send-mail"]
    check outcome.survey.waitInsights.len > 0
    check flowHealthJson(savePlanJson(plan), jsonl)["grade"].getStr().len > 0
    check analyzeAdapterEventsJson(savePlanJson(plan), jsonl)[
      "survey"]["waitInsights"].len > 0

    let output = generateReportsFromAdapterEvents(plan, events)
    check output.reportMarkdown.contains("## KPI dashboard")
    check output.reportHtml.contains("<!doctype html>")
    check generateReportsFromAdapterEventsJson(savePlanJson(plan), jsonl)[
      "files"].len == 6

  test "writes rotated reports and exports event streams":
    let root = getTempDir() / "flowcaptain-public-api-test"
    if dirExists(root):
      removeDir(root)

    let plan = samplePlan()
    let events = sampleEvents()
    let written = writeReportsFromAdapterEvents(plan, events,
      rootDir = root, runId = "run-1", retentionDays = 30)
    check fileExists(written.latestDir / "captain-report.html")
    check fileExists(written.runDir / "manifest.json")

    let comparison = comparePlanVariants(plan, fasterPlan())
    exportMetricEventsJsonl(comparison, root / "metrics" / "events.jsonl")
    exportAdapterEventsJsonl(events, root / "adapter" / "events.jsonl")
    check fileExists(root / "metrics" / "events.jsonl")
    check fileExists(root / "adapter" / "events.jsonl")

  test "rejects malformed plan and dependency failures at the public boundary":
    expect JsonParsingError:
      discard loadPlanJson("{")

    expect ValueError:
      discard loadPlanJson($(%*{"id": "bad", "title": "Bad", "nodes": {}}))

    let invalid = invalidReferencePlan()
    let invalidJson = savePlanJson(invalid)
    let validation = validatePlanJson(invalidJson)
    check not validation["ok"].getBool()
    check validation["errors"].len > 0

    let dry = dryRunPlanJson(invalidJson)
    check not dry["ok"].getBool()
    check dry["errors"].len > 0

    expect ValueError:
      discard dependencyBatches(invalid)

    let executed = executePlan(invalid)
    check not executed.run.ok
    check executed.run.errors.len > 0

    let cycle = cyclicPlan()
    let cycleDry = dryRunPlan(cycle)
    check not cycleDry.ok
    check cycleDry.errors.len > 0

  test "handles failed executions, health penalties, and failure JSON shape":
    let outcome = executePlan(failingPlan())
    check not outcome.run.ok
    check outcome.analysis.failedNodes == @["calculate"]
    check outcome.analysis.retryCount == 2
    check outcome.health().score < 100.0

    let payload = outcomeJson(outcome)
    check payload["run"]["ok"].getBool() == false
    check payload["analysis"]["failedNodes"][0].getStr() == "calculate"
    check payload["analysis"]["retryCount"].getInt() == 2
    check payload["health"]["failureRate"].getFloat() > 0.0
    check payload["survey"]["operationalSummary"]["failureRate"].getFloat() > 0.0

  test "rejects malformed adapter JSONL and reports unmatched adapter events":
    expect ValueError:
      discard importEventsJsonl("not-json")

    expect ValueError:
      discard importEventsJsonl($(%*{
        "schemaVersion": 2,
        "eventType": "nodeFinished",
        "flowId": "billing",
        "runId": "run-1"
      }))

    expect ValueError:
      discard importEventsJsonl($(%*{
        "schemaVersion": 1,
        "eventType": "nodeFinished",
        "flowId": "billing",
        "runId": "run-1",
        "durationMs": -1
      }))

    let tooLarge = repeat("x", MaxAdapterEventLineBytes + 1)
    expect ValueError:
      discard importEventsJsonl(tooLarge)

    let unmatched = @[adapterEvent("nodeFinished", "other-flow", "run-1",
      variantId = "A", nodeId = "load-users", durationMs = 10,
      status = nsSucceeded)]
    let outcome = analyzeAdapterEvents(samplePlan(), unmatched)
    check not outcome.run.ok
    check outcome.run.errors[0].contains("no adapter events matched")

  test "supports report artifact JSON, keepLatest false, and root-level exports":
    let root = getTempDir() / "flowcaptain-public-api-options-test"
    if dirExists(root):
      removeDir(root)
    createDir(root)

    let comparison = comparePlanVariants(samplePlan(), fasterPlan())
    let files = reportArtifactsJson(comparison)["files"]
    check files.len == 6
    check files[0]["fileName"].getStr() == "captain-report.md"

    let written = writeReports(comparison, rootDir = root / "reports",
      runId = "no-latest", keepLatest = false)
    check written.latestDir.len == 0
    check fileExists(written.runDir / "captain-report.html")
    check not fileExists(root / "reports" / "captain-report.html")

    let cwd = getCurrentDir()
    setCurrentDir(root)
    try:
      exportMetricEventsJsonl(comparison, "metrics.jsonl")
      exportAdapterEventsJsonl(sampleEvents(), "adapter.jsonl")
    finally:
      setCurrentDir(cwd)
    check fileExists(root / "metrics.jsonl")
    check fileExists(root / "adapter.jsonl")

  test "bridges FlowBrigade control plans without reimplementing policy logic":
    let plan = samplePlan()
    let policy = workerBackpressurePolicy(
      name = "billing-worker",
      rate = 1,
      per = 1.sec,
      burst = 1,
      concurrency = 2
    )
    let controlPlan = initFlowBrigadePlan(
      "billing-control",
      requiredCapabilities = [fbckRateLimit, fbckBulkhead, fbckRetry],
      policies = [policy]
    )

    let report = validateControlBridge(plan, controlPlan)
    check report.ok
    check report.flowId == "billing"
    check report.flowBrigadePlan.policyReports.len == 1
    check report.flowBrigadePlan.policyReports[0].hasRetry
    check report.flowBrigadePlan.policyReports[0].hasBulkhead
    check controlBridgeJson(report)["flowBrigadePlan"]["policyReports"].len == 1
    check flowBrigadeCapabilitiesJson().len > 5

    let inspected = inspectControlPolicy(policy, "worker:billing")
    check inspected.allowed
    check inspected.limit >= 1

    let first = allowControlPolicy(policy, "worker:billing")
    let second = allowControlPolicy(policy, "worker:billing")
    check first.allowed
    check not second.allowed
    check second.retryAfterMs >= 0
    check controlDecisionJson(second)["allowed"].getBool() == false

  test "reports invalid FlowBrigade control bridge configuration":
    let plan = invalidReferencePlan()
    var registry = initLimiterRegistry()
    registry.addLimiter("present", fixedWindowDefinition(limit = 1, per = 1.min))
    let brokenPolicy = initFlowPolicy(
      kind = fpkWorkerBackpressure,
      name = "broken",
      primaryLimiter = "missing",
      registry = registry
    )
    let controlPlan = initFlowBrigadePlan("broken-control", policies = [brokenPolicy])

    let report = validateControlBridge(plan, controlPlan)
    check not report.ok
    check report.errors.anyIt(it.contains("flow plan:"))
    check report.errors.anyIt(it.contains("control plan:"))
    let payload = controlBridgeJson(report)
    check payload["ok"].getBool() == false
    check payload["flowBrigadePlan"]["policyReports"][0]["issues"][0]["kind"].getStr() == "missingLimiter"
