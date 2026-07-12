import flowcaptain

proc main() =
  var totalReports = 0
  for i in 0 ..< 1000:
    var plan = initCaptainPlan("plan-" & $i, "Plan " & $i, variant = "A")
    plan.nodes.add node("extract-" & $i, "Extract", plannedMs = 10)
    plan.nodes.add node("transform-" & $i, "Transform", plannedMs = 20)
    plan.nodes.add node("load-" & $i, "Load", plannedMs = 5)
    plan.edges.add edge("edge-a-" & $i, plan.nodes[0].id, plan.nodes[1].id)
    plan.edges.add edge("edge-b-" & $i, plan.nodes[1].id, plan.nodes[2].id)
    var candidate = initCaptainPlan("plan-" & $i, "Plan " & $i, variant = "B")
    candidate.nodes.add node("extract-" & $i, "Extract", plannedMs = 10)
    candidate.nodes.add node("load-" & $i, "Load", plannedMs = 15)
    candidate.edges.add edge("edge-fast-" & $i, candidate.nodes[0].id, candidate.nodes[1].id)
    let comparison = compare(plan.execute().complete(), candidate.execute().complete())
    discard markdownReport(comparison)
    discard htmlReport(comparison)
    inc totalReports

  doAssert totalReports == 1000

main()
