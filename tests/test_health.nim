import std/[json, unittest]

import flowcaptain

suite "flow health":
  test "scores a clean completed flow highly":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract", plannedMs = 100))
    plan.nodes.add(node("publish", "Publish", plannedMs = 100))
    plan.edges.add(edge("extract-publish", "extract", "publish"))

    let outcome = plan.execute().complete().attachSurveyor()
    let scored = outcome.health()
    check scored.score >= 75.0
    check scored.failureRate == 0.0
    check scored.reasons.len > 0

  test "penalizes failures, retries, and waits":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract", plannedMs = 100))
    plan.nodes.add(node("publish", "Publish", plannedMs = 100, fail = true,
                        retries = 2))
    plan.edges.add(edge("extract-publish", "extract", "publish"))

    var outcome = plan.execute().complete().attachSurveyor()
    outcome.survey.waitInsights.add(CaptainWaitInsight(
      edgeId: "extract-publish",
      fromNode: "extract",
      toNode: "publish",
      blockedCount: 1,
      totalWaitMs: 100,
      averageWaitMs: 100.0,
      reason: "test wait"
    ))
    let scored = outcome.health()
    check scored.score < 75.0
    check scored.failureRate > 0.0
    check scored.retryRate > 0.0
    check scored.toJson()["grade"].getStr().len > 0
