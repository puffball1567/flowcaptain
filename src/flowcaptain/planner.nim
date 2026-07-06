import std/[sets, tables]

import ./types
import ./validation

proc nodeIds(plan: CaptainPlan): seq[string] =
  for item in plan.nodes:
    result.add(item.id)

proc readyBatches*(plan: CaptainPlan): DryRun =
  let checked = plan.validate()
  if not checked.ok:
    return DryRun(ok: false, batches: @[], errors: checked.errors)

  var incoming = initTable[string, int]()
  var outgoing = initTable[string, seq[string]]()
  for id in plan.nodeIds():
    incoming[id] = 0
    outgoing[id] = @[]
  for item in plan.edges:
    incoming[item.toNode] = incoming[item.toNode] + 1
    outgoing[item.fromNode].add(item.toNode)

  var completed = initHashSet[string]()
  var batches: seq[seq[string]] = @[]
  while completed.len < plan.nodes.len:
    var batch: seq[string] = @[]
    for id in plan.nodeIds():
      if id notin completed and incoming[id] == 0:
        batch.add(id)
    if batch.len == 0:
      return DryRun(ok: false, batches: batches,
                    errors: @["cycle detected or no ready nodes remain"])
    batches.add(batch)
    for id in batch:
      completed.incl(id)
      for target in outgoing[id]:
        incoming[target] = incoming[target] - 1

  DryRun(ok: true, batches: batches, errors: @[])
