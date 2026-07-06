import std/unittest

import flowcaptain

suite "runner":
  test "runs simulated work in dependency batches":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract", plannedMs = 10))
    plan.nodes.add(node("publish", "Publish", plannedMs = 20))
    plan.edges.add(edge("extract-publish", "extract", "publish"))

    let outcome = plan.execute().complete()
    check outcome.run.ok
    check outcome.run.totalMs == 30
    check outcome.run.timeline.len == 2
    check outcome.analysis.criticalPath == @["extract", "publish"]

  test "skips required downstream work after failure":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract", plannedMs = 10, fail = true, retries = 2))
    plan.nodes.add(node("publish", "Publish", plannedMs = 20))
    plan.edges.add(edge("extract-publish", "extract", "publish"))

    let outcome = plan.execute().complete()
    check not outcome.run.ok
    check outcome.run.timeline[0].status == nsFailed
    check outcome.run.timeline[1].status == nsSkipped
    check outcome.analysis.retryCount == 2
