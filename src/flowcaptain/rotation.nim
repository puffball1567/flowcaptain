import std/[os, strutils, times]

import ./types

type
  ReportRotationOptions* = object
    rootDir*: string
    runId*: string
    retentionDays*: Natural
    keepLatest*: bool

  ReportWriteResult* = object
    latestDir*: string
    runDir*: string
    removedRunDirs*: seq[string]

proc defaultReportRotationOptions*(rootDir = "reports"; runId = "";
    retentionDays: Natural = 30; keepLatest = true): ReportRotationOptions =
  ReportRotationOptions(rootDir: rootDir, runId: runId,
    retentionDays: retentionDays, keepLatest: keepLatest)

proc sanitizePathPart(value: string): string =
  let source = if value.len == 0: now().utc.format("yyyyMMdd'T'HHmmss'Z'") else: value
  for ch in source:
    if ch.isAlphaNumeric or ch in {'-', '_', '.'}:
      result.add(ch)
    else:
      result.add('-')

proc runDir(rootDir, runId: string): string =
  rootDir / "runs" / sanitizePathPart(runId)

proc writeArtifacts(dir: string; output: CaptainArtifacts) =
  createDir(dir)
  writeFile(dir / "captain-report.md", output.reportMarkdown)
  writeFile(dir / "captain-report.html", output.reportHtml)
  writeFile(dir / "flow.mmd", output.flowMermaid)
  writeFile(dir / "structure.mmd", output.structureMermaid)
  writeFile(dir / "comparison.mmd", output.comparisonMermaid)
  writeFile(dir / "manifest.json", output.manifestJson)

proc removeExpiredRuns(rootDir: string; retentionDays: Natural): seq[string] =
  if retentionDays == 0:
    return
  let runsRoot = rootDir / "runs"
  if not dirExists(runsRoot):
    return
  let cutoff = getTime() - initDuration(days = int(retentionDays))
  for kind, path in walkDir(runsRoot):
    if kind != pcDir:
      continue
    let info = getFileInfo(path)
    if info.lastWriteTime < cutoff:
      removeDir(path)
      result.add(path)

proc writeRotatedReports*(output: CaptainArtifacts;
    options = defaultReportRotationOptions()): ReportWriteResult =
  let root = if options.rootDir.len == 0: "reports" else: options.rootDir
  createDir(root)

  if options.keepLatest:
    root.writeArtifacts(output)
    result.latestDir = root

  result.runDir = runDir(root, options.runId)
  result.runDir.writeArtifacts(output)
  result.removedRunDirs = removeExpiredRuns(root, options.retentionDays)
