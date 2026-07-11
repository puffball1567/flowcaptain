import std/[strutils, unittest]

import flowcaptain

suite "shared ids":
  test "normalizes surrounding whitespace":
    let checked = checkSharedId("  billing:daily-1  ", sikFlow)
    check checked.ok
    check checked.normalized == "billing:daily-1"

  test "rejects empty, oversized, and unsafe ids":
    check not checkSharedId("   ", sikNode).ok
    check not checkSharedId(repeat("a", MaxSharedIdLen + 1), sikNode).ok
    check not checkSharedId("node/name", sikNode).ok

  test "validation resolves references using normalized ids":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node(" extract ", "Extract"))
    plan.nodes.add(node("publish", "Publish"))
    plan.edges.add(edge("extract-publish", "extract", " publish "))
    check plan.validate().ok
