import std/[json, strutils, unittest]

import flowcaptain

suite "metric events":
  test "exports time-series friendly metric events":
    var a = initCaptainPlan("daily-report", "Daily Report", variant = "A")
    a.nodes.add(node("extract", "Extract", plannedMs = 120))
    a.nodes.add(node("transform", "Transform", plannedMs = 850))
    a.nodes.add(node("publish", "Publish", plannedMs = 90))
    a.edges.add(edge("extract-transform", "extract", "transform"))
    a.edges.add(edge("transform-publish", "transform", "publish"))

    var b = initCaptainPlan("daily-report", "Daily Report", variant = "B")
    b.nodes.add(node("extract", "Extract", plannedMs = 120))
    b.nodes.add(node("transform-a", "Transform A", plannedMs = 430))
    b.nodes.add(node("transform-b", "Transform B", plannedMs = 410))
    b.nodes.add(node("publish", "Publish", plannedMs = 95))
    b.edges.add(edge("extract-a", "extract", "transform-a"))
    b.edges.add(edge("extract-b", "extract", "transform-b"))
    b.edges.add(edge("a-publish", "transform-a", "publish"))
    b.edges.add(edge("b-publish", "transform-b", "publish"))

    let comparison = compare(a.execute().complete(), b.execute().complete())
    let events = comparison.metricEvents()
    check events.len > 10
    check events[0].schemaVersion == 1
    check events[0].flowId == "daily-report"
    check events[0].runId == "daily-report:B"

    var hasRunCritical = false
    var hasNodeDuration = false
    var hasEdgeWait = false
    var hasDataQuality = false
    for item in events:
      if item.kind == "run" and item.metricName == "criticalPathMs":
        hasRunCritical = true
      if item.kind == "node" and item.nodeId == "transform-a" and
          item.metricName == "durationMs":
        hasNodeDuration = true
      if item.kind == "edge" and item.metricName == "waitMs":
        hasEdgeWait = true
      if item.kind == "dataQuality" and item.metricName == "timingCoverage":
        hasDataQuality = true

    check hasRunCritical
    check hasNodeDuration
    check hasEdgeWait
    check hasDataQuality

    let jsonEvents = comparison.metricEventsJson()
    check jsonEvents.kind == JArray
    check jsonEvents.len == events.len
    check jsonEvents[0]["schemaVersion"].getInt() == 1

    let lines = comparison.metricEventsJsonLines()
    check lines.contains("\"kind\":\"run\"")
    check lines.contains("\"metricName\":\"criticalPathMs\"")
    check lines.splitLines().len == events.len
