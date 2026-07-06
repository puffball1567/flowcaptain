import std/os

import flowcaptain

proc baselinePlan(): CaptainPlan =
  result = initCaptainPlan("daily-report", "Daily Report", variant = "A")
  result.nodes.add(node("extract", "Extract", plannedMs = 120))
  result.nodes.add(node("transform", "Transform", plannedMs = 850))
  result.nodes.add(node("publish", "Publish", plannedMs = 90))
  result.edges.add(edge("extract-transform", "extract", "transform"))
  result.edges.add(edge("transform-publish", "transform", "publish"))

proc candidatePlan(): CaptainPlan =
  result = initCaptainPlan("daily-report", "Daily Report", variant = "B")
  result.nodes.add(node("extract", "Extract", plannedMs = 120))
  result.nodes.add(node("transform-a", "Transform A", plannedMs = 430))
  result.nodes.add(node("transform-b", "Transform B", plannedMs = 410))
  result.nodes.add(node("publish", "Publish", plannedMs = 95))
  result.edges.add(edge("extract-transform-a", "extract", "transform-a"))
  result.edges.add(edge("extract-transform-b", "extract", "transform-b"))
  result.edges.add(edge("transform-a-publish", "transform-a", "publish"))
  result.edges.add(edge("transform-b-publish", "transform-b", "publish"))

let baseline = baselinePlan().execute().complete()
let candidate = candidatePlan().execute().complete()
let comparison = compare(baseline, candidate)
let output = artifacts(comparison)

let written = output.writeRotatedReports(defaultReportRotationOptions(
  rootDir = "reports",
  runId = "daily-report-" & candidate.run.variant,
  retentionDays = 30,
  keepLatest = true
))

echo "Generated:"
echo "- reports/captain-report.md"
echo "- reports/flow.mmd"
echo "- reports/comparison.mmd"
echo "- reports/manifest.json"
echo "- " & written.runDir / "captain-report.md"
