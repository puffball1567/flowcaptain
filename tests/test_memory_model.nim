import std/unittest
import flowcaptain

suite "memory model":
  test "uses Nim ARC memory manager":
    when defined(gcArc):
      check true
    else:
      check false

  test "creates and releases captain plans under ARC":
    var totalEdges = 0
    for i in 0 ..< 200:
      var plan = initCaptainPlan("plan-" & $i, "Plan " & $i, variant = "A")
      plan.nodes.add node("extract-" & $i, "Extract", plannedMs = 10)
      plan.nodes.add node("load-" & $i, "Load", plannedMs = 20)
      plan.edges.add edge("edge-" & $i, plan.nodes[0].id, plan.nodes[1].id)
      check validate(plan).ok
      totalEdges += plan.edges.len
    check totalEdges == 200
