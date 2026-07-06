import std/unittest

import flowcaptain

suite "analysis":
  test "comparison selects faster critical path":
    var a = initCaptainPlan("daily", "Daily", variant = "A")
    a.nodes.add(node("extract", "Extract", plannedMs = 100))
    a.nodes.add(node("transform", "Transform", plannedMs = 800))
    a.nodes.add(node("publish", "Publish", plannedMs = 100))
    a.edges.add(edge("extract-transform", "extract", "transform"))
    a.edges.add(edge("transform-publish", "transform", "publish"))

    var b = initCaptainPlan("daily", "Daily", variant = "B")
    b.nodes.add(node("extract", "Extract", plannedMs = 100))
    b.nodes.add(node("transform-a", "Transform A", plannedMs = 350))
    b.nodes.add(node("transform-b", "Transform B", plannedMs = 350))
    b.nodes.add(node("publish", "Publish", plannedMs = 100))
    b.edges.add(edge("extract-a", "extract", "transform-a"))
    b.edges.add(edge("extract-b", "extract", "transform-b"))
    b.edges.add(edge("a-publish", "transform-a", "publish"))
    b.edges.add(edge("b-publish", "transform-b", "publish"))

    let comparison = compare(a.execute().complete(), b.execute().complete())
    check comparison.betterVariant == "B"
    check comparison.deltaMs < 0
    check comparison.summary.len > 0
