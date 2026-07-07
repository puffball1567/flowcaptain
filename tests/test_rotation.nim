import std/[os, times, unittest]

import flowcaptain

suite "report rotation":
  test "writes latest files and run snapshot":
    let root = getTempDir() / "flowcaptain-rotation-current"
    if dirExists(root):
      removeDir(root)

    let output = CaptainArtifacts(
      reportMarkdown: "# Report",
      reportHtml: "<!doctype html>",
      flowMermaid: "flowchart LR",
      structureMermaid: "classDiagram",
      comparisonMermaid: "flowchart LR",
      manifestJson: "{}"
    )

    let written = output.writeRotatedReports(defaultReportRotationOptions(
      rootDir = root,
      runId = "run:one",
      retentionDays = 30,
      keepLatest = true
    ))

    check fileExists(root / "captain-report.md")
    check fileExists(root / "captain-report.html")
    check fileExists(root / "flow.mmd")
    check fileExists(root / "structure.mmd")
    check fileExists(root / "comparison.mmd")
    check fileExists(root / "manifest.json")
    check fileExists(written.runDir / "captain-report.md")
    check written.runDir.endsWith("run-one")
    check written.removedRunDirs.len == 0

    removeDir(root)

  test "removes run snapshots older than retention period":
    let root = getTempDir() / "flowcaptain-rotation-retention"
    if dirExists(root):
      removeDir(root)
    createDir(root / "runs" / "old")
    writeFile(root / "runs" / "old" / "captain-report.md", "old")
    setLastModificationTime(root / "runs" / "old",
      getTime() - initDuration(days = 10))

    let output = CaptainArtifacts(
      reportMarkdown: "# Report",
      reportHtml: "<!doctype html>",
      flowMermaid: "flowchart LR",
      structureMermaid: "classDiagram",
      comparisonMermaid: "flowchart LR",
      manifestJson: "{}"
    )

    let written = output.writeRotatedReports(defaultReportRotationOptions(
      rootDir = root,
      runId = "new",
      retentionDays = 3,
      keepLatest = false
    ))

    check not dirExists(root / "runs" / "old")
    check fileExists(root / "runs" / "new" / "captain-report.md")
    check written.latestDir.len == 0
    check written.removedRunDirs.len == 1

    removeDir(root)
