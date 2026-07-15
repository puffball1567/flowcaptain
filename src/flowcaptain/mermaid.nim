import std/[sets, strutils, tables]

import ./types

proc statusByNode(outcome: CaptainOutcome): Table[string, NodeStatus] =
  for item in outcome.run.timeline:
    result[item.nodeId] = item.status

proc criticalSet(outcome: CaptainOutcome): HashSet[string] =
  for id in outcome.analysis.criticalPath:
    result.incl(id)

proc mermaidId(value: string): string =
  result = "n_"
  for ch in value:
    if ch in {'a'..'z'} or ch in {'A'..'Z'} or ch in {'0'..'9'} or ch == '_':
      result.add(ch)
    else:
      result.add('_')

proc mermaidLabel(value: string): string =
  value.replace("\"", "&quot;")

proc classValue(value: string): string =
  result = value
  result = result.replace("\"", "'")
  result = result.replace("{", "(")
  result = result.replace("}", ")")
  result = result.replace("<", "(")
  result = result.replace(">", ")")
  result = result.replace("\n", " ")

proc statusByNodeRun(outcome: CaptainOutcome): Table[string, NodeRun] =
  for item in outcome.run.timeline:
    result[item.nodeId] = item

proc mermaid*(outcome: CaptainOutcome): string =
  let statuses = outcome.statusByNode()
  let critical = outcome.criticalSet()
  result.add("flowchart LR\n")
  for item in outcome.plan.nodes:
    let status = statuses.getOrDefault(item.id, nsPending)
    let id = item.id.mermaidId()
    let label = item.title.mermaidLabel() & "<br/>" & $item.plannedMs & "ms"
    result.add("  " & id & "[\"" & label & "\"]\n")
    if status == nsFailed:
      result.add("  " & id & ":::failed\n")
    elif item.id == outcome.analysis.slowestNode:
      result.add("  " & id & ":::slow\n")
    elif item.id in critical:
      result.add("  " & id & ":::critical\n")
  for edge in outcome.plan.edges:
    let label = if edge.kind == ekOptional: "|optional|" else: ""
    result.add("  " & edge.fromNode.mermaidId() & " -->" & label & " " &
               edge.toNode.mermaidId() & "\n")
  result.add("  classDef slow fill:#ffe0b2,stroke:#ef6c00;\n")
  result.add("  classDef failed fill:#ffcdd2,stroke:#c62828;\n")
  result.add("  classDef critical fill:#dcedc8,stroke:#558b2f;\n")

proc structureMermaid*(outcome: CaptainOutcome): string =
  let runs = outcome.statusByNodeRun()
  let critical = outcome.criticalSet()
  result.add("classDiagram\n")
  result.add("  class CaptainPlan {\n")
  result.add("    +id " & outcome.plan.id.classValue() & "\n")
  result.add("    +title " & outcome.plan.title.classValue() & "\n")
  result.add("    +variant " & outcome.plan.variant.classValue() & "\n")
  result.add("    +nodes " & $outcome.plan.nodes.len & "\n")
  result.add("    +edges " & $outcome.plan.edges.len & "\n")
  result.add("  }\n")
  result.add("  class CaptainRun {\n")
  result.add("    +ok " & $outcome.run.ok & "\n")
  result.add("    +totalMs " & $outcome.run.totalMs & "\n")
  result.add("    +criticalPathMs " & $outcome.analysis.criticalPathMs & "\n")
  result.add("    +retryCount " & $outcome.analysis.retryCount & "\n")
  result.add("  }\n")
  result.add("  CaptainPlan --> CaptainRun : produces\n")

  for item in outcome.plan.nodes:
    let classId = item.id.mermaidId()
    let run = runs.getOrDefault(item.id, NodeRun(
      nodeId: item.id,
      title: item.title,
      status: nsPending,
      durationMs: item.plannedMs
    ))
    result.add("  class " & classId & " {\n")
    result.add("    +id " & item.id.classValue() & "\n")
    result.add("    +title " & item.title.classValue() & "\n")
    result.add("    +expectedMs " & $item.plannedMs & "\n")
    result.add("    +status " & $run.status & "\n")
    result.add("    +durationMs " & $run.durationMs & "\n")
    result.add("    +retries " & $run.retries & "\n")
    if item.id in critical:
      result.add("    +criticalPath true\n")
    result.add("  }\n")
    result.add("  CaptainPlan --> " & classId & " : contains\n")

  for edge in outcome.plan.edges:
    let relation =
      if edge.kind == ekOptional: "optional"
      elif edge.waitOn: "required waitOn"
      else: "required"
    result.add("  " & edge.fromNode.mermaidId() & " --> " &
      edge.toNode.mermaidId() & " : " & relation & "\n")

proc comparisonMermaid*(comparison: VariantComparison): string =
  result.add("flowchart LR\n")
  let basePrefix = comparison.baseline.plan.variant.mermaidId()
  let candidatePrefix = comparison.candidate.plan.variant.mermaidId()
  result.add("  subgraph " & comparison.baseline.plan.variant.mermaidLabel() & "\n")
  for edge in comparison.baseline.plan.edges:
    result.add("    " & basePrefix & "_" & edge.fromNode.mermaidId() & "[\"" &
               edge.fromNode.mermaidLabel() & "\"] --> " & basePrefix & "_" &
               edge.toNode.mermaidId() & "[\"" & edge.toNode.mermaidLabel() & "\"]\n")
  result.add("  end\n")
  result.add("  subgraph " & comparison.candidate.plan.variant.mermaidLabel() & "\n")
  for edge in comparison.candidate.plan.edges:
    result.add("    " & candidatePrefix & "_" & edge.fromNode.mermaidId() & "[\"" &
               edge.fromNode.mermaidLabel() & "\"] --> " & candidatePrefix & "_" &
               edge.toNode.mermaidId() & "[\"" & edge.toNode.mermaidLabel() & "\"]\n")
  result.add("  end\n")
