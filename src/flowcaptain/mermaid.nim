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
