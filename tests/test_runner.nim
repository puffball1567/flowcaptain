import std/unittest

import flowcaptain
import flowworkrunner

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

  test "executes through FlowDependency and FlowWorkRunner":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract", plannedMs = 10))
    plan.nodes.add(node("transform-a", "Transform A", plannedMs = 30))
    plan.nodes.add(node("transform-b", "Transform B", plannedMs = 20))
    plan.nodes.add(node("publish", "Publish", plannedMs = 5))
    plan.edges.add(edge("extract-a", "extract", "transform-a"))
    plan.edges.add(edge("extract-b", "extract", "transform-b"))
    plan.edges.add(edge("a-publish", "transform-a", "publish"))
    plan.edges.add(edge("b-publish", "transform-b", "publish"))

    let outcome = plan.executeWithToolkit().complete()

    check outcome.run.ok
    check outcome.dryRun.batches == @[
      @["extract"],
      @["transform-a", "transform-b"],
      @["publish"]
    ]
    check outcome.run.totalMs == 45
    check outcome.run.timeline.len == 4
    check outcome.analysis.criticalPath == @["extract", "transform-a", "publish"]

  test "toolkit execution skips downstream work after WorkRunner failure":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract", plannedMs = 10, fail = true, retries = 2))
    plan.nodes.add(node("publish", "Publish", plannedMs = 20))
    plan.edges.add(edge("extract-publish", "extract", "publish"))

    let outcome = plan.executeWithToolkit().complete()

    check not outcome.run.ok
    check outcome.run.timeline[0].status == nsFailed
    check outcome.run.timeline[1].status == nsSkipped
    check outcome.analysis.retryCount == 2

  test "toolkit execution accepts custom WorkRunner executors":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract", plannedMs = 10))
    plan.nodes.add(node("publish", "Publish", plannedMs = 20))
    plan.edges.add(edge("extract-publish", "extract", "publish"))

    var executors = initWorkExecutorRegistry()
    executors.register("extract", proc(node: WorkNode): WorkTaskResult =
      succeeded(node.id, durationMillis = 7, message = "custom extract")
    )
    executors.register("publish", proc(node: WorkNode): WorkTaskResult =
      succeeded(node.id, durationMillis = 11, message = "custom publish")
    )

    let outcome = plan.executeWithToolkit(executors).complete()

    check outcome.run.ok
    check outcome.run.totalMs == 18
    check outcome.run.timeline[0].message == "custom extract"
    check outcome.run.timeline[1].message == "custom publish"

  test "toolkit execution rejects invalid Captain plans before lower layers":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract", plannedMs = -1))

    let outcome = plan.executeWithToolkit()

    check not outcome.dryRun.ok
    check not outcome.run.ok
    check outcome.run.errors == @["node plannedMs must be >= 0: extract"]
