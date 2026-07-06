import std/[sets, strutils]

import ./types

const MaxIdLen* = 160

proc validId(id: string): bool =
  if id.len == 0 or id.len > MaxIdLen:
    return false
  for ch in id:
    if not (ch.isAlphaNumeric or ch in {'-', '_', '.', ':'}):
      return false
  true

proc validate*(plan: CaptainPlan): ValidationResult =
  var errors: seq[string] = @[]
  if not validId(plan.id):
    errors.add("plan id is invalid")
  if plan.title.strip.len == 0:
    errors.add("plan title must not be empty")
  if plan.nodes.len == 0:
    errors.add("plan must contain at least one node")

  var nodeIds = initHashSet[string]()
  for item in plan.nodes:
    if not validId(item.id):
      errors.add("node id is invalid: " & item.id)
    if item.id in nodeIds:
      errors.add("duplicate node id: " & item.id)
    nodeIds.incl(item.id)
    if item.title.strip.len == 0:
      errors.add("node title must not be empty: " & item.id)
    if item.plannedMs < 0:
      errors.add("node plannedMs must be >= 0: " & item.id)
    if item.retries < 0:
      errors.add("node retries must be >= 0: " & item.id)

  var edgeIds = initHashSet[string]()
  for item in plan.edges:
    if not validId(item.id):
      errors.add("edge id is invalid: " & item.id)
    if item.id in edgeIds:
      errors.add("duplicate edge id: " & item.id)
    edgeIds.incl(item.id)
    if item.fromNode notin nodeIds:
      errors.add("edge references missing fromNode: " & item.id)
    if item.toNode notin nodeIds:
      errors.add("edge references missing toNode: " & item.id)
    if item.fromNode == item.toNode:
      errors.add("edge cannot point to the same node: " & item.id)

  if errors.len == 0:
    validationOk()
  else:
    validationFailure(errors)
