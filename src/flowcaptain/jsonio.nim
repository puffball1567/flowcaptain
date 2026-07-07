import std/[json, strutils]

import ./types

proc edgeKindText(kind: EdgeKind): string =
  case kind
  of ekRequired: "required"
  of ekOptional: "optional"

proc parseEdgeKind(value: string): EdgeKind =
  case value.normalize()
  of "", "required", "ekrequired":
    ekRequired
  of "optional", "ekoptional":
    ekOptional
  else:
    raise newException(ValueError, "invalid edge kind: " & value)

proc toJson*(plan: CaptainPlan): JsonNode =
  result = %*{
    "schemaVersion": 1,
    "id": plan.id,
    "title": plan.title,
    "variant": plan.variant,
    "nodes": [],
    "edges": []
  }
  for item in plan.nodes:
    result["nodes"].add(%*{
      "id": item.id,
      "title": item.title,
      "plannedMs": item.plannedMs
    })
  for item in plan.edges:
    result["edges"].add(%*{
      "id": item.id,
      "fromNode": item.fromNode,
      "toNode": item.toNode,
      "kind": item.kind.edgeKindText(),
      "waitOn": item.waitOn
    })

proc planFromJson*(value: JsonNode): CaptainPlan =
  if value.kind != JObject:
    raise newException(ValueError, "plan JSON must be an object")
  result = initCaptainPlan(
    value{"id"}.getStr(),
    value{"title"}.getStr(),
    variant = value{"variant"}.getStr("A")
  )
  let nodes = value{"nodes"}
  if nodes == nil or nodes.kind != JArray:
    raise newException(ValueError, "plan nodes must be an array")
  for item in nodes:
    if item.kind != JObject:
      raise newException(ValueError, "plan node must be an object")
    result.nodes.add(node(
      item{"id"}.getStr(),
      item{"title"}.getStr(item{"id"}.getStr()),
      plannedMs = item{"plannedMs"}.getInt(0)
    ))
  let edges = value{"edges"}
  if edges != nil:
    if edges.kind != JArray:
      raise newException(ValueError, "plan edges must be an array")
    for item in edges:
      if item.kind != JObject:
        raise newException(ValueError, "plan edge must be an object")
      result.edges.add(edge(
        item{"id"}.getStr(),
        item{"fromNode"}.getStr(),
        item{"toNode"}.getStr(),
        kind = item{"kind"}.getStr("required").parseEdgeKind(),
        waitOn = item{"waitOn"}.getBool(true)
      ))

proc toJson*(artifacts: CaptainArtifacts): JsonNode =
  %*{
    "schemaVersion": 1,
    "files": [
      {"fileName": "captain-report.md", "mediaType": "text/markdown",
       "byteSize": artifacts.reportMarkdown.len},
      {"fileName": "captain-report.html", "mediaType": "text/html",
       "byteSize": artifacts.reportHtml.len},
      {"fileName": "flow.mmd", "mediaType": "text/vnd.mermaid",
       "byteSize": artifacts.flowMermaid.len},
      {"fileName": "structure.mmd", "mediaType": "text/vnd.mermaid",
       "byteSize": artifacts.structureMermaid.len},
      {"fileName": "comparison.mmd", "mediaType": "text/vnd.mermaid",
       "byteSize": artifacts.comparisonMermaid.len},
      {"fileName": "manifest.json", "mediaType": "application/json",
       "byteSize": artifacts.manifestJson.len}
    ]
  }

proc manifestJson*(reportMarkdown, reportHtml, flowMermaid, structureMermaid,
    comparisonMermaid: string): string =
  var manifest = ""
  for _ in 0 .. 5:
    let partial = CaptainArtifacts(reportMarkdown: reportMarkdown,
                                   reportHtml: reportHtml,
                                   flowMermaid: flowMermaid,
                                   structureMermaid: structureMermaid,
                                   comparisonMermaid: comparisonMermaid,
                                   manifestJson: manifest)
    let next = $partial.toJson()
    if next == manifest:
      break
    manifest = next
  manifest
