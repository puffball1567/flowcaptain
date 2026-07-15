import std/[json, os, strutils, unittest]

import flowcaptain

proc baselinePlan(): CaptainPlan =
  result = initCaptainPlan("daily-report", "Daily Report", variant = "A")
  result.nodes.add(node("extract", "Extract", plannedMs = 120))
  result.nodes.add(node("transform", "Transform", plannedMs = 850))
  result.nodes.add(node("publish", "Publish", plannedMs = 90))
  result.edges.add(edge("extract-transform", "extract", "transform"))
  result.edges.add(edge("transform-publish", "transform", "publish"))

proc candidatePlan(): CaptainPlan =
  result = initCaptainPlan("daily-report", "Daily Report", variant = "B")
  result.nodes.add(node("extract", "Extract", plannedMs = 120))
  result.nodes.add(node("transform-a", "Transform A", plannedMs = 430))
  result.nodes.add(node("transform-b", "Transform B", plannedMs = 410))
  result.nodes.add(node("publish", "Publish", plannedMs = 95))
  result.edges.add(edge("extract-a", "extract", "transform-a"))
  result.edges.add(edge("extract-b", "extract", "transform-b"))
  result.edges.add(edge("a-publish", "transform-a", "publish"))
  result.edges.add(edge("b-publish", "transform-b", "publish"))

suite "history":
  test "serializes run snapshots as JSONL and detects improvement":
    let baseline = baselinePlan().execute().complete().attachSurveyor()
    let candidate = candidatePlan().execute().complete().attachSurveyor()
    let snapshots = @[
      baseline.historySnapshot(runId = "run-a", recordedAtMs = 1_000),
      candidate.historySnapshot(runId = "run-b", recordedAtMs = 2_000)
    ]

    let lines = snapshots.historySnapshotsJsonLines()
    check lines.splitLines().len == 2

    let parsed = lines.parseHistorySnapshotsJsonLines()
    check parsed.len == 2
    check parsed[0].runId == "run-a"
    check parsed[1].criticalPathMs < parsed[0].criticalPathMs

    let trend = parsed.historyTrend()
    check trend.ok
    check trend.criticalPathMsDelta < 0
    check trend.totalWaitMsDelta >= 0
    check trend.latestRunId == "run-b"
    check trend.toJson()["criticalPathMsDelta"].getInt() < 0

  test "reports degradation when retries, failures, or wait grow":
    var previous = baselinePlan().execute().complete().attachSurveyor()
    var latest = previous
    latest.run.timeline[1].retries = 2
    latest.run.timeline[1].status = nsFailed
    latest.run.ok = false
    latest.analysis.retryCount = 2
    latest.analysis.failedNodes = @["transform"]
    latest.survey = CaptainSurveyInsights()
    latest = latest.attachSurveyor()

    let trend = @[
      previous.historySnapshot(runId = "previous"),
      latest.historySnapshot(runId = "latest")
    ].historyTrend()

    check trend.ok
    check trend.degraded
    check not trend.improved
    check trend.retryCountDelta > 0
    check trend.failedNodeCountDelta > 0
    check trend.recommendations.len > 0

  test "rejects invalid history input and requires two snapshots":
    let one = @[baselinePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "one")]
    let trend = one.historyTrend()
    check not trend.ok
    check trend.summary.contains("at least two")

    expect ValueError:
      discard "{\"schemaVersion\":2,\"flowId\":\"x\",\"runId\":\"r\"}".
        parseHistorySnapshotsJsonLines()

    expect ValueError:
      discard "{\"schemaVersion\":1,\"flowId\":\"x\"".
        parseHistorySnapshotsJsonLines()

  test "rejects negative history durations and counters":
    var snapshot = baselinePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "bad")
    snapshot.totalMs = -1

    expect ValueError:
      discard ($snapshot.toJson()).parseHistorySnapshotsJsonLines()

    snapshot.totalMs = 1
    snapshot.retryCount = -1

    expect ValueError:
      discard ($snapshot.toJson()).parseHistorySnapshotsJsonLines()

  test "marks degraded when only wait grows":
    var previous = baselinePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "previous")
    var latest = previous
    latest.runId = "latest"
    latest.totalWaitMs = previous.totalWaitMs + 250

    let trend = @[previous, latest].historyTrend()
    check trend.ok
    check trend.degraded
    check not trend.improved
    check trend.totalWaitMsDelta == 250
    check trend.recommendations.join(" ").contains("wait")

  test "marks degraded when only health score drops":
    var previous = baselinePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "previous")
    var latest = previous
    latest.runId = "latest"
    latest.healthScore = previous.healthScore - 5.0

    let trend = @[previous, latest].historyTrend()
    check trend.ok
    check trend.degraded
    check not trend.improved
    check trend.healthScoreDelta < 0

  test "compares only the latest two history snapshots":
    var first = baselinePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "first")
    var previous = first
    previous.runId = "previous"
    previous.criticalPathMs = 1_000
    var latest = previous
    latest.runId = "latest"
    latest.criticalPathMs = 1_100

    let trend = @[first, previous, latest].historyTrend()
    check trend.ok
    check trend.previousRunId == "previous"
    check trend.latestRunId == "latest"
    check trend.criticalPathMsDelta == 100

  test "exposes history through the public integration API":
    let baseline = baselinePlan().executePlan()
    let candidate = candidatePlan().executePlan()
    let snapshots = @[
      snapshotRun(baseline, runId = "public-a"),
      snapshotRun(candidate, runId = "public-b")
    ]

    let jsonl = historyJsonl(snapshots)
    check importHistoryJsonl(jsonl).len == 2
    let trendJson = historyTrendJson(importHistoryJsonl(jsonl))
    check trendJson["ok"].getBool()
    check trendJson["latestRunId"].getStr() == "public-b"

  test "stores and loads history snapshots from local files":
    let root = getTempDir() / "flowcaptain-history-file-test"
    if dirExists(root):
      removeDir(root)
    let path = root / "nested" / "daily-report.jsonl"
    let baseline = baselinePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "file-a")
    let candidate = candidatePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "file-b")

    appendHistorySnapshotFile(path, baseline)
    appendHistorySnapshotFile(path, candidate)

    let loaded = loadHistorySnapshotsFile(path)
    check loaded.len == 2
    check loaded[0].runId == "file-a"
    check loaded[1].runId == "file-b"
    check loaded.historyTrend().ok

    let rewritePath = root / "rewrite.jsonl"
    writeHistorySnapshotsFile(rewritePath, @[candidate])
    check loadHistorySnapshotsFile(rewritePath).len == 1
    check loadHistorySnapshotsFile(root / "missing.jsonl").len == 0

  test "stores and loads history snapshots from sqlite":
    let root = getTempDir() / "flowcaptain-history-sqlite-test"
    if dirExists(root):
      removeDir(root)
    let path = root / "history.sqlite3"
    let first = baselinePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "sqlite-a")
    let second = candidatePlan().execute().complete().attachSurveyor().
      historySnapshot(runId = "sqlite-b")
    var other = first
    other.flowId = "other-flow"
    other.runId = "sqlite-other"

    appendHistorySnapshotSqlite(path, first)
    appendHistorySnapshotSqlite(path, second)
    appendHistorySnapshotSqlite(path, other)

    let all = loadHistorySnapshotsSqlite(path)
    check all.len == 3
    let filtered = loadHistorySnapshotsSqlite(path, flowId = "daily-report")
    check filtered.len == 2
    check filtered[0].runId == "sqlite-a"
    check filtered[1].runId == "sqlite-b"
    check filtered.historyTrend().ok

    let publicLoaded = loadHistorySqlite(path, flowId = "other-flow")
    check publicLoaded.len == 1
    check publicLoaded[0].runId == "sqlite-other"
