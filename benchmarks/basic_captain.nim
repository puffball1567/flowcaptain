import std/[monotimes, strformat, times]

import flowcaptain

var plan = initCaptainPlan("bench", "Benchmark")
for index in 0 ..< 1000:
  let id = "n" & $index
  plan.nodes.add(node(id, "Node " & $index, plannedMs = 1))
  if index > 0:
    plan.edges.add(edge("e" & $index, "n" & $(index - 1), id))

let started = getMonoTime()
let outcome = plan.execute().complete()
let elapsed = getMonoTime() - started

doAssert outcome.run.ok
echo &"captain: {plan.nodes.len} nodes, {plan.edges.len} edges in {elapsed.inMilliseconds} ms"
