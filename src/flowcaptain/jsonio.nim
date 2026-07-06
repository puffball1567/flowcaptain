import std/[json]

import ./types

proc toJson*(artifacts: CaptainArtifacts): JsonNode =
  %*{
    "schemaVersion": 1,
    "files": [
      {"fileName": "captain-report.md", "mediaType": "text/markdown",
       "byteSize": artifacts.reportMarkdown.len},
      {"fileName": "flow.mmd", "mediaType": "text/vnd.mermaid",
       "byteSize": artifacts.flowMermaid.len},
      {"fileName": "comparison.mmd", "mediaType": "text/vnd.mermaid",
       "byteSize": artifacts.comparisonMermaid.len},
      {"fileName": "manifest.json", "mediaType": "application/json",
       "byteSize": artifacts.manifestJson.len}
    ]
  }

proc manifestJson*(reportMarkdown, flowMermaid, comparisonMermaid: string): string =
  var manifest = ""
  for _ in 0 .. 5:
    let partial = CaptainArtifacts(reportMarkdown: reportMarkdown,
                                   flowMermaid: flowMermaid,
                                   comparisonMermaid: comparisonMermaid,
                                   manifestJson: manifest)
    let next = $partial.toJson()
    if next == manifest:
      break
    manifest = next
  manifest
