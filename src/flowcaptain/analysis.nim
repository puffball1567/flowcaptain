import std/tables

import ./types

proc durations(run: CaptainRun): Table[string, int] =
  for item in run.timeline:
    result[item.nodeId] = item.durationMs

proc predecessors(plan: CaptainPlan): Table[string, seq[string]] =
  for item in plan.nodes:
    result[item.id] = @[]
  for item in plan.edges:
    result[item.toNode].add(item.fromNode)

proc analyze*(plan: CaptainPlan; run: CaptainRun): CaptainAnalysis =
  let duration = run.durations()
  let prev = plan.predecessors()
  var distance = initTable[string, int]()
  var previous = initTable[string, string]()

  for item in plan.nodes:
    var best = 0
    var bestPrev = ""
    for source in prev[item.id]:
      let candidate = distance.getOrDefault(source, 0)
      if candidate > best:
        best = candidate
        bestPrev = source
    distance[item.id] = best + duration.getOrDefault(item.id, item.plannedMs)
    if bestPrev.len > 0:
      previous[item.id] = bestPrev

  var endNode = ""
  var criticalMs = 0
  for id, value in distance:
    if value > criticalMs:
      criticalMs = value
      endNode = id

  var path: seq[string] = @[]
  var cursor = endNode
  while cursor.len > 0:
    path.insert(cursor, 0)
    cursor = previous.getOrDefault(cursor, "")

  var slowest = ""
  var slowestMs = -1
  var failed: seq[string] = @[]
  var retries = 0
  for item in run.timeline:
    if item.durationMs > slowestMs:
      slowestMs = item.durationMs
      slowest = item.nodeId
    if item.status == nsFailed:
      failed.add(item.nodeId)
    retries = retries + item.retries

  var recommendation = "No change recommended."
  if failed.len > 0:
    recommendation = "Investigate failed nodes before optimizing duration."
  elif slowest.len > 0 and slowest in path:
    recommendation = "Review `" & slowest & "` because it is slow and on the critical path."
  elif slowest.len > 0:
    recommendation = "Review `" & slowest & "` as the slowest observed node."

  CaptainAnalysis(criticalPath: path, criticalPathMs: criticalMs,
                  slowestNode: slowest, slowestNodeMs: max(slowestMs, 0),
                  failedNodes: failed, retryCount: retries,
                  recommendation: recommendation)

proc complete*(outcome: CaptainOutcome): CaptainOutcome =
  result = outcome
  result.analysis = analyze(outcome.plan, outcome.run)
