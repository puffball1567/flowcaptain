import std/[json, unittest]

import flowcaptain

suite "plan diff":
  test "reports structural changes and breaking removals":
    var baseline = initCaptainPlan("billing", "Billing", variant = "A")
    baseline.nodes.add(node("extract", "Extract", plannedMs = 100))
    baseline.nodes.add(node("transform", "Transform", plannedMs = 200))
    baseline.nodes.add(node("publish", "Publish", plannedMs = 50))
    baseline.edges.add(edge("extract-transform", "extract", "transform"))
    baseline.edges.add(edge("transform-publish", "transform", "publish"))

    var candidate = initCaptainPlan("billing", "Billing", variant = "B")
    candidate.nodes.add(node("extract", "Extract", plannedMs = 80))
    candidate.nodes.add(node("transform-a", "Transform A", plannedMs = 100))
    candidate.nodes.add(node("transform-b", "Transform B", plannedMs = 100))
    candidate.nodes.add(node("publish", "Publish", plannedMs = 50))
    candidate.edges.add(edge("extract-transform-a", "extract", "transform-a"))
    candidate.edges.add(edge("extract-transform-b", "extract", "transform-b"))
    candidate.edges.add(edge("transform-publish", "transform-a", "publish"))

    let diff = diffPlans(baseline, candidate)
    check diff.changes.len >= 6
    check diff.breakingChanges.len >= 2
    check diff.summary.contains("breaking changes")

  test "serializes plan diff for reports and artifacts":
    var baseline = initCaptainPlan("daily", "Daily")
    baseline.nodes.add(node("a", "A"))

    var candidate = initCaptainPlan("daily", "Daily")
    candidate.nodes.add(node("a", "A", plannedMs = 10))
    candidate.nodes.add(node("b", "B"))

    let payload = diffPlans(baseline, candidate).toJson()
    check payload["schemaVersion"].getInt() == 1
    check payload["changes"].len == 2
    check payload["breakingChanges"].len == 0
