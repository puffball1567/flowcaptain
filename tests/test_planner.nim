import std/unittest

import flowcaptain

suite "planner":
  test "computes dry-run batches":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("extract", "Extract"))
    plan.nodes.add(node("transform-a", "Transform A"))
    plan.nodes.add(node("transform-b", "Transform B"))
    plan.nodes.add(node("publish", "Publish"))
    plan.edges.add(edge("extract-a", "extract", "transform-a"))
    plan.edges.add(edge("extract-b", "extract", "transform-b"))
    plan.edges.add(edge("a-publish", "transform-a", "publish"))
    plan.edges.add(edge("b-publish", "transform-b", "publish"))

    let dry = plan.readyBatches()
    check dry.ok
    check dry.batches == @[@["extract"], @["transform-a", "transform-b"], @["publish"]]

  test "detects cycles":
    var plan = initCaptainPlan("cycle", "Cycle")
    plan.nodes.add(node("a", "A"))
    plan.nodes.add(node("b", "B"))
    plan.edges.add(edge("a-b", "a", "b"))
    plan.edges.add(edge("b-a", "b", "a"))
    let dry = plan.readyBatches()
    check not dry.ok
    check dry.errors.len > 0
