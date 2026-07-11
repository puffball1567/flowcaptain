import std/[json, os, parseopt]

import flowcaptain

type
  CliOptions = object
    planPath: string
    eventsPath: string
    outDir: string
    runId: string
    help: bool

proc usage(): string =
  """
flowcaptain_event_report --plan plan.json --events events.jsonl --out reports [--run-id run-1]

Generate browser-readable FlowCaptain reports from framework adapter JSONL events.

Options:
  --plan      FlowCaptain plan JSON.
  --events    Adapter event JSON Lines.
  --out       Output directory. Defaults to reports.
  --run-id    Optional run id filter.
  --help      Show this help.
"""

proc assignOption(options: var CliOptions; key, value: string) =
  case key
  of "plan", "p":
    options.planPath = value
  of "events", "e":
    options.eventsPath = value
  of "out", "o":
    options.outDir = value
  of "run-id", "r":
    options.runId = value
  else:
    raise newException(ValueError, "unknown option: " & key)

proc parseCliOptions(): CliOptions =
  result.outDir = "reports"
  var parser = initOptParser(commandLineParams())
  var pending = ""

  for kind, key, value in parser.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        result.help = true
      else:
        if value.len == 0:
          pending = key
        else:
          result.assignOption(key, value)
    of cmdArgument:
      if pending.len == 0:
        raise newException(ValueError, "unexpected argument: " & key)
      result.assignOption(pending, key)
      pending = ""
    of cmdEnd:
      discard
  if pending.len > 0:
    raise newException(ValueError, "missing value for option: " & pending)

proc requireFile(path, label: string) =
  if path.len == 0:
    raise newException(ValueError, label & " is required")
  if not fileExists(path):
    raise newException(ValueError, label & " does not exist: " & path)

proc filterRun(events: seq[CaptainAdapterEvent]; runId: string):
    seq[CaptainAdapterEvent] =
  if runId.len == 0:
    return events
  for item in events:
    if item.runId == runId:
      result.add(item)

proc singleRunComparison(outcome: CaptainOutcome): VariantComparison =
  VariantComparison(
    baseline: outcome,
    candidate: outcome,
    deltaMs: 0,
    betterVariant: outcome.plan.variant,
    summary: "Single observed run for `" & outcome.plan.id & "`.",
    surveySummary: "Adapter event import completed.",
    improvements: @[],
    regressions: @[]
  )

proc main() =
  let options = parseCliOptions()
  if options.help:
    stdout.write(usage())
    return

  requireFile(options.planPath, "--plan")
  requireFile(options.eventsPath, "--events")

  let plan = parseJson(readFile(options.planPath)).planFromJson()
  let events = readFile(options.eventsPath).parseAdapterEventsJsonLines()
  let selectedEvents = events.filterRun(options.runId)
  let outcome = plan.outcomeFromAdapterEvents(selectedEvents)
  let output = artifacts(outcome.singleRunComparison())
  let written = output.writeRotatedReports(defaultReportRotationOptions(
    rootDir = options.outDir,
    runId = if options.runId.len > 0: options.runId else: outcome.run.planId & "-" & outcome.run.variant,
    retentionDays = 0,
    keepLatest = true
  ))

  echo "Generated:"
  echo "- " & written.latestDir / "captain-report.html"
  echo "- " & written.latestDir / "captain-report.md"
  echo "- " & written.latestDir / "manifest.json"
  echo "- " & written.runDir / "captain-report.html"

when isMainModule:
  try:
    main()
  except CatchableError as exc:
    stderr.writeLine("flowcaptain_event_report: " & exc.msg)
    quit(1)
