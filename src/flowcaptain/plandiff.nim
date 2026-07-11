import std/[tables]

import ./types

proc edgeText(edge: CaptainEdge): string =
  let kind =
    case edge.kind
    of ekRequired: "required"
    of ekOptional: "optional"
  edge.fromNode & " -> " & edge.toNode & " (" & kind &
    ", waitOn=" & $edge.waitOn & ")"

proc change(kind: PlanChangeKind; targetId, before, after, message: string;
    breaking = false): PlanChange =
  PlanChange(kind: kind, targetId: targetId, before: before, after: after,
             breaking: breaking, message: message)

proc nodeMap(plan: CaptainPlan): OrderedTable[string, CaptainNode] =
  result = initOrderedTable[string, CaptainNode]()
  for item in plan.nodes:
    result[item.id] = item

proc edgeMap(plan: CaptainPlan): OrderedTable[string, CaptainEdge] =
  result = initOrderedTable[string, CaptainEdge]()
  for item in plan.edges:
    result[item.id] = item

proc addChange(diff: var PlanDiff; item: PlanChange) =
  diff.changes.add item
  if item.breaking:
    diff.breakingChanges.add item

proc diffPlans*(baseline, candidate: CaptainPlan): PlanDiff =
  result = PlanDiff(baselineId: baseline.id, candidateId: candidate.id,
                    changes: @[], breakingChanges: @[], summary: "")

  let baselineNodes = baseline.nodeMap()
  let candidateNodes = candidate.nodeMap()
  for id, item in baselineNodes:
    if not candidateNodes.hasKey(id):
      result.addChange(change(pckNodeRemoved, id, item.title, "",
        "node removed: " & id, breaking = true))
  for id, item in candidateNodes:
    if not baselineNodes.hasKey(id):
      result.addChange(change(pckNodeAdded, id, "", item.title,
        "node added: " & id))
    else:
      let before = baselineNodes[id]
      if before.title != item.title:
        result.addChange(change(pckNodeTitleChanged, id, before.title,
          item.title, "node title changed: " & id))
      if before.plannedMs != item.plannedMs:
        result.addChange(change(pckNodePlannedMsChanged, id, $before.plannedMs,
          $item.plannedMs, "node planned duration changed: " & id))

  let baselineEdges = baseline.edgeMap()
  let candidateEdges = candidate.edgeMap()
  for id, item in baselineEdges:
    if not candidateEdges.hasKey(id):
      result.addChange(change(pckEdgeRemoved, id, item.edgeText(), "",
        "edge removed: " & id, breaking = true))
  for id, item in candidateEdges:
    if not baselineEdges.hasKey(id):
      result.addChange(change(pckEdgeAdded, id, "", item.edgeText(),
        "edge added: " & id))
    else:
      let before = baselineEdges[id]
      if before.fromNode != item.fromNode or before.toNode != item.toNode:
        result.addChange(change(pckEdgeEndpointChanged, id,
          before.fromNode & " -> " & before.toNode,
          item.fromNode & " -> " & item.toNode,
          "edge endpoint changed: " & id, breaking = true))
      if before.kind != item.kind:
        result.addChange(change(pckEdgeKindChanged, id, $before.kind,
          $item.kind, "edge kind changed: " & id))
      if before.waitOn != item.waitOn:
        result.addChange(change(pckEdgeWaitChanged, id, $before.waitOn,
          $item.waitOn, "edge wait behavior changed: " & id))

  if result.changes.len == 0:
    result.summary = "no plan structure changes"
  else:
    result.summary = $result.changes.len & " plan changes"
    if result.breakingChanges.len > 0:
      result.summary.add("; " & $result.breakingChanges.len &
        " breaking changes")
