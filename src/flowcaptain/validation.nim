import std/[sets, strutils]

import ./types
import ./ids

proc validate*(plan: CaptainPlan): ValidationResult =
  var errors: seq[string] = @[]
  let planId = plan.id.checkSharedId(sikFlow)
  if not planId.ok:
    errors.add("plan id is invalid: " & planId.error)
  if plan.title.strip.len == 0:
    errors.add("plan title must not be empty")
  if plan.nodes.len == 0:
    errors.add("plan must contain at least one node")

  var nodeIds = initHashSet[string]()
  for item in plan.nodes:
    let nodeId = item.id.checkSharedId(sikNode)
    if not nodeId.ok:
      errors.add("node id is invalid: " & item.id)
    if nodeId.normalized in nodeIds:
      errors.add("duplicate node id: " & nodeId.normalized)
    nodeIds.incl(nodeId.normalized)
    if item.title.strip.len == 0:
      errors.add("node title must not be empty: " & item.id)
    if item.plannedMs < 0:
      errors.add("node expectedMs must be >= 0: " & item.id)
    if item.retries < 0:
      errors.add("node retries must be >= 0: " & item.id)

  var edgeIds = initHashSet[string]()
  for item in plan.edges:
    let edgeId = item.id.checkSharedId(sikEdge)
    if not edgeId.ok:
      errors.add("edge id is invalid: " & item.id)
    if edgeId.normalized in edgeIds:
      errors.add("duplicate edge id: " & edgeId.normalized)
    edgeIds.incl(edgeId.normalized)
    let fromNode = item.fromNode.normalizeSharedId()
    let toNode = item.toNode.normalizeSharedId()
    if fromNode notin nodeIds:
      errors.add("edge references missing fromNode: " & item.id)
    if toNode notin nodeIds:
      errors.add("edge references missing toNode: " & item.id)
    if fromNode == toNode:
      errors.add("edge cannot point to the same node: " & item.id)

  if errors.len == 0:
    validationOk()
  else:
    validationFailure(errors)
