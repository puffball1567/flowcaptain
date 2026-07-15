import std/[json, strformat, strutils]

import ./health
import ./types

const HistorySnapshotSchemaVersion* = 1

proc totalWorkMs(outcome: CaptainOutcome): int =
  for item in outcome.run.timeline:
    result.inc item.durationMs

proc totalWaitMs(outcome: CaptainOutcome): int =
  for item in outcome.survey.waitInsights:
    result.inc item.totalWaitMs

proc defaultRunId(outcome: CaptainOutcome): string =
  outcome.plan.id & ":" & outcome.plan.variant

proc historySnapshot*(outcome: CaptainOutcome; runId = "";
    recordedAtMs = 0): CaptainHistorySnapshot =
  let scored = outcome.health()
  let ops = outcome.survey.operationalSummary
  CaptainHistorySnapshot(
    schemaVersion: HistorySnapshotSchemaVersion,
    flowId: outcome.plan.id,
    runId: if runId.len > 0: runId else: outcome.defaultRunId(),
    variantId: outcome.plan.variant,
    recordedAtMs: recordedAtMs,
    ok: outcome.run.ok,
    totalMs: outcome.run.totalMs,
    criticalPathMs: outcome.analysis.criticalPathMs,
    totalWorkMs: outcome.totalWorkMs(),
    totalWaitMs: outcome.totalWaitMs(),
    retryCount: outcome.analysis.retryCount,
    failedNodeCount: outcome.analysis.failedNodes.len,
    healthScore: scored.score,
    healthGrade: scored.grade,
    averageCycleTimeMs: ops.averageCycleTimeMs,
    throughputPerHour: ops.throughputPerHour,
    failureRate: ops.failureRate,
    defectRate: ops.defectRate,
    retryRate: ops.retryRate,
    firstPassYield: ops.firstPassYield
  )

proc toJson*(snapshot: CaptainHistorySnapshot): JsonNode =
  %*{
    "schemaVersion": snapshot.schemaVersion,
    "flowId": snapshot.flowId,
    "runId": snapshot.runId,
    "variantId": snapshot.variantId,
    "recordedAtMs": snapshot.recordedAtMs,
    "ok": snapshot.ok,
    "totalMs": snapshot.totalMs,
    "criticalPathMs": snapshot.criticalPathMs,
    "totalWorkMs": snapshot.totalWorkMs,
    "totalWaitMs": snapshot.totalWaitMs,
    "retryCount": snapshot.retryCount,
    "failedNodeCount": snapshot.failedNodeCount,
    "healthScore": snapshot.healthScore,
    "healthGrade": snapshot.healthGrade,
    "averageCycleTimeMs": snapshot.averageCycleTimeMs,
    "throughputPerHour": snapshot.throughputPerHour,
    "failureRate": snapshot.failureRate,
    "defectRate": snapshot.defectRate,
    "retryRate": snapshot.retryRate,
    "firstPassYield": snapshot.firstPassYield
  }

proc historySnapshotFromJson*(node: JsonNode): CaptainHistorySnapshot =
  if node.kind != JObject:
    raise newException(ValueError, "history snapshot must be a JSON object")
  result = CaptainHistorySnapshot(
    schemaVersion: Natural(node{"schemaVersion"}.getInt(HistorySnapshotSchemaVersion)),
    flowId: node{"flowId"}.getStr(),
    runId: node{"runId"}.getStr(),
    variantId: node{"variantId"}.getStr(),
    recordedAtMs: node{"recordedAtMs"}.getInt(),
    ok: node{"ok"}.getBool(),
    totalMs: node{"totalMs"}.getInt(),
    criticalPathMs: node{"criticalPathMs"}.getInt(),
    totalWorkMs: node{"totalWorkMs"}.getInt(),
    totalWaitMs: node{"totalWaitMs"}.getInt(),
    retryCount: node{"retryCount"}.getInt(),
    failedNodeCount: node{"failedNodeCount"}.getInt(),
    healthScore: node{"healthScore"}.getFloat(),
    healthGrade: node{"healthGrade"}.getStr(),
    averageCycleTimeMs: node{"averageCycleTimeMs"}.getFloat(),
    throughputPerHour: node{"throughputPerHour"}.getFloat(),
    failureRate: node{"failureRate"}.getFloat(),
    defectRate: node{"defectRate"}.getFloat(),
    retryRate: node{"retryRate"}.getFloat(),
    firstPassYield: node{"firstPassYield"}.getFloat()
  )
  if result.schemaVersion != HistorySnapshotSchemaVersion:
    raise newException(ValueError, "unsupported history snapshot schemaVersion")
  if result.flowId.len == 0:
    raise newException(ValueError, "history snapshot flowId is required")
  if result.runId.len == 0:
    raise newException(ValueError, "history snapshot runId is required")
  if result.totalMs < 0 or result.criticalPathMs < 0 or
      result.totalWorkMs < 0 or result.totalWaitMs < 0:
    raise newException(ValueError, "history snapshot durations must be >= 0")
  if result.retryCount < 0 or result.failedNodeCount < 0:
    raise newException(ValueError, "history snapshot counters must be >= 0")

proc historySnapshotsJsonLines*(snapshots: openArray[CaptainHistorySnapshot]):
    string =
  for item in snapshots:
    if result.len > 0:
      result.add("\n")
    result.add($item.toJson())

proc parseHistorySnapshotsJsonLines*(content: string):
    seq[CaptainHistorySnapshot] =
  var lineNumber = 0
  for rawLine in content.splitLines():
    inc lineNumber
    let line = rawLine.strip()
    if line.len == 0:
      continue
    try:
      result.add(parseJson(line).historySnapshotFromJson())
    except JsonParsingError as exc:
      raise newException(ValueError, "invalid history JSON at line " &
        $lineNumber & ": " & exc.msg)
    except ValueError as exc:
      raise newException(ValueError, "invalid history snapshot at line " &
        $lineNumber & ": " & exc.msg)

proc trendSummary(previous, latest: CaptainHistorySnapshot): string =
  let criticalDelta = latest.criticalPathMs - previous.criticalPathMs
  let healthDelta = latest.healthScore - previous.healthScore
  if criticalDelta < 0 and healthDelta >= 0:
    return &"Run {latest.runId} improved critical path by {-criticalDelta} ms without lowering health."
  if criticalDelta > 0:
    return &"Run {latest.runId} increased critical path by {criticalDelta} ms."
  if healthDelta < 0:
    return &"Run {latest.runId} lowered health score by {-healthDelta:.1f}."
  &"Run {latest.runId} is stable against {previous.runId}."

proc historyTrend*(snapshots: openArray[CaptainHistorySnapshot]):
    CaptainHistoryTrend =
  result.snapshotCount = snapshots.len
  if snapshots.len < 2:
    result.ok = false
    result.summary = "at least two history snapshots are required"
    result.recommendations.add("Record another run before evaluating trend.")
    return

  let previous = snapshots[^2]
  let latest = snapshots[^1]
  result.ok = true
  result.previousRunId = previous.runId
  result.latestRunId = latest.runId
  result.totalMsDelta = latest.totalMs - previous.totalMs
  result.criticalPathMsDelta = latest.criticalPathMs - previous.criticalPathMs
  result.totalWorkMsDelta = latest.totalWorkMs - previous.totalWorkMs
  result.totalWaitMsDelta = latest.totalWaitMs - previous.totalWaitMs
  result.retryCountDelta = latest.retryCount - previous.retryCount
  result.failedNodeCountDelta = latest.failedNodeCount - previous.failedNodeCount
  result.healthScoreDelta = latest.healthScore - previous.healthScore
  result.degraded = result.criticalPathMsDelta > 0 or result.totalWaitMsDelta > 0 or
    result.retryCountDelta > 0 or result.failedNodeCountDelta > 0 or
    result.healthScoreDelta < 0
  result.improved = result.criticalPathMsDelta < 0 and
    result.retryCountDelta <= 0 and result.failedNodeCountDelta <= 0 and
    result.healthScoreDelta >= 0
  result.summary = trendSummary(previous, latest)

  if result.criticalPathMsDelta > 0:
    result.recommendations.add("Review nodes on the critical path before adding parallel work elsewhere.")
  if result.totalWaitMsDelta > 0:
    result.recommendations.add("Investigate dependency handoff wait growth.")
  if result.retryCountDelta > 0:
    result.recommendations.add("Retries increased; inspect unstable nodes before optimizing throughput.")
  if result.failedNodeCountDelta > 0:
    result.recommendations.add("Failed node count increased; treat reliability as the first bottleneck.")
  if result.recommendations.len == 0 and result.improved:
    result.recommendations.add("Keep the latest flow variant as a candidate baseline.")

proc toJson*(trend: CaptainHistoryTrend): JsonNode =
  result = %*{
    "schemaVersion": 1,
    "ok": trend.ok,
    "snapshotCount": trend.snapshotCount,
    "previousRunId": trend.previousRunId,
    "latestRunId": trend.latestRunId,
    "totalMsDelta": trend.totalMsDelta,
    "criticalPathMsDelta": trend.criticalPathMsDelta,
    "totalWorkMsDelta": trend.totalWorkMsDelta,
    "totalWaitMsDelta": trend.totalWaitMsDelta,
    "retryCountDelta": trend.retryCountDelta,
    "failedNodeCountDelta": trend.failedNodeCountDelta,
    "healthScoreDelta": trend.healthScoreDelta,
    "degraded": trend.degraded,
    "improved": trend.improved,
    "summary": trend.summary,
    "recommendations": []
  }
  for item in trend.recommendations:
    result["recommendations"].add(%item)

