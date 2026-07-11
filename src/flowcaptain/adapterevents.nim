import std/[algorithm, json, strutils, tables]

import ./analysis
import ./planner
import ./surveyor
import ./types
import ./validation

const
  AdapterEventSchemaVersion* = 1
  MaxAdapterEventLineBytes* = 1024 * 1024
  MaxAdapterEvents* = 100_000

proc statusText(status: NodeStatus): string =
  case status
  of nsPending: "pending"
  of nsSucceeded: "succeeded"
  of nsFailed: "failed"
  of nsSkipped: "skipped"

proc parseStatus(value: string): NodeStatus =
  case value.normalize()
  of "", "pending", "nspending":
    nsPending
  of "ok", "success", "succeeded", "complete", "completed", "nssucceeded":
    nsSucceeded
  of "fail", "failed", "error", "nsfailed":
    nsFailed
  of "skip", "skipped", "nsskipped":
    nsSkipped
  else:
    raise newException(ValueError, "invalid adapter event status: " & value)

proc adapterEvent*(eventType, flowId, runId: string; variantId = "";
    nodeId = ""; edgeId = ""; timestampMs = 0; durationMs = 0;
    status = nsPending; retryCount = 0; errorKind = ""; message = "";
    tags = initOrderedTable[string, string]()): CaptainAdapterEvent =
  CaptainAdapterEvent(
    schemaVersion: AdapterEventSchemaVersion,
    eventType: eventType,
    flowId: flowId,
    runId: runId,
    variantId: variantId,
    nodeId: nodeId,
    edgeId: edgeId,
    timestampMs: timestampMs,
    durationMs: durationMs,
    status: status,
    retryCount: retryCount,
    errorKind: errorKind,
    message: message,
    tags: tags
  )

proc toJson*(event: CaptainAdapterEvent): JsonNode =
  var tags = newJObject()
  for key, value in event.tags:
    tags[key] = %value
  %*{
    "schemaVersion": event.schemaVersion,
    "eventType": event.eventType,
    "flowId": event.flowId,
    "runId": event.runId,
    "variantId": event.variantId,
    "nodeId": event.nodeId,
    "edgeId": event.edgeId,
    "timestampMs": event.timestampMs,
    "durationMs": event.durationMs,
    "status": event.status.statusText(),
    "retryCount": event.retryCount,
    "errorKind": event.errorKind,
    "message": event.message,
    "tags": tags
  }

proc adapterEventFromJson*(node: JsonNode): CaptainAdapterEvent =
  if node.kind != JObject:
    raise newException(ValueError, "adapter event must be a JSON object")

  result = adapterEvent(
    node{"eventType"}.getStr(),
    node{"flowId"}.getStr(),
    node{"runId"}.getStr(),
    variantId = node{"variantId"}.getStr(),
    nodeId = node{"nodeId"}.getStr(),
    edgeId = node{"edgeId"}.getStr(),
    timestampMs = node{"timestampMs"}.getInt(),
    durationMs = node{"durationMs"}.getInt(),
    status = node{"status"}.getStr().parseStatus(),
    retryCount = node{"retryCount"}.getInt(),
    errorKind = node{"errorKind"}.getStr(),
    message = node{"message"}.getStr()
  )
  result.schemaVersion = Natural(node{"schemaVersion"}.getInt(AdapterEventSchemaVersion))

  let tags = node{"tags"}
  if tags != nil and tags.kind == JObject:
    for key, value in tags:
      result.tags[key] = value.getStr()

  if result.schemaVersion != AdapterEventSchemaVersion:
    raise newException(ValueError, "unsupported adapter event schemaVersion")
  if result.eventType.len == 0:
    raise newException(ValueError, "adapter event eventType is required")
  if result.flowId.len == 0:
    raise newException(ValueError, "adapter event flowId is required")
  if result.runId.len == 0:
    raise newException(ValueError, "adapter event runId is required")
  if result.durationMs < 0:
    raise newException(ValueError, "adapter event durationMs must be >= 0")
  if result.retryCount < 0:
    raise newException(ValueError, "adapter event retryCount must be >= 0")

proc adapterEventsJsonLines*(events: openArray[CaptainAdapterEvent]): string =
  for item in events:
    if result.len > 0:
      result.add("\n")
    result.add($item.toJson())

proc parseAdapterEventsJsonLines*(content: string): seq[CaptainAdapterEvent] =
  var count = 0
  var lineNumber = 0
  for rawLine in content.splitLines():
    inc lineNumber
    let line = rawLine.strip()
    if line.len == 0:
      continue
    if line.len > MaxAdapterEventLineBytes:
      raise newException(ValueError, "adapter event line is too large: " &
        $lineNumber)
    inc count
    if count > MaxAdapterEvents:
      raise newException(ValueError, "too many adapter events")
    try:
      result.add(parseJson(line).adapterEventFromJson())
    except JsonParsingError as exc:
      raise newException(ValueError, "invalid adapter event JSON at line " &
        $lineNumber & ": " & exc.msg)
    except KeyError as exc:
      raise newException(ValueError, "invalid adapter event at line " &
        $lineNumber & ": " & exc.msg)

proc eventOrder(a, b: CaptainAdapterEvent): int =
  cmp(a.timestampMs, b.timestampMs)

proc nodeTitle(plan: CaptainPlan; nodeId: string): string =
  for item in plan.nodes:
    if item.id == nodeId:
      return item.title
  nodeId

proc edgeById(plan: CaptainPlan): Table[string, CaptainEdge] =
  for item in plan.edges:
    result[item.id] = item

type
  NodeObservation = object
    nodeId: string
    started: bool
    finished: bool
    startedMs: int
    finishedMs: int
    durationMs: int
    status: NodeStatus
    retryCount: int
    errorKind: string
    message: string

proc terminalStatus(event: CaptainAdapterEvent): NodeStatus =
  let normalized = event.eventType.normalize()
  if normalized == "nodefailed":
    nsFailed
  elif normalized == "nodeskipped":
    nsSkipped
  elif event.status == nsPending:
    nsSucceeded
  else:
    event.status

proc outcomeFromAdapterEvents*(plan: CaptainPlan;
    events: openArray[CaptainAdapterEvent]): CaptainOutcome =
  let planValidation = validate(plan)
  if not planValidation.ok:
    return CaptainOutcome(
      plan: plan,
      dryRun: DryRun(ok: false, errors: planValidation.errors),
      run: CaptainRun(planId: plan.id, variant: plan.variant, ok: false,
        errors: planValidation.errors)
    )

  var selected: seq[CaptainAdapterEvent] = @[]
  var errors: seq[string] = @[]
  var runId = ""
  for item in events:
    if item.flowId != plan.id:
      continue
    if item.variantId.len > 0 and item.variantId != plan.variant:
      continue
    if runId.len == 0:
      runId = item.runId
    if item.runId == runId:
      selected.add(item)

  if selected.len == 0:
    let message = "no adapter events matched plan and variant"
    return CaptainOutcome(
      plan: plan,
      dryRun: DryRun(ok: false, errors: @[message]),
      run: CaptainRun(planId: plan.id, variant: plan.variant, ok: false,
        errors: @[message])
    )

  selected.sort(eventOrder)
  var observations = initOrderedTable[string, NodeObservation]()
  var explicitWaits: seq[CaptainWaitInsight] = @[]
  let edges = plan.edgeById()
  var baseMs = 0
  var hasBase = false
  var fallbackClock = 0

  for item in selected:
    let normalized = item.eventType.normalize()
    if normalized == "runstarted" and item.timestampMs > 0 and not hasBase:
      baseMs = item.timestampMs
      hasBase = true
      continue

    if normalized == "edgewaitobserved":
      if item.edgeId.len == 0:
        errors.add("edge wait adapter event is missing edgeId")
        continue
      let edge = edges.getOrDefault(item.edgeId)
      explicitWaits.add(CaptainWaitInsight(
        edgeId: item.edgeId,
        fromNode: edge.fromNode,
        toNode: edge.toNode,
        blockedCount: 1,
        totalWaitMs: max(0, item.durationMs),
        averageWaitMs: max(0, item.durationMs).float,
        reason: if item.message.len > 0: item.message else: "adapter observed edge wait"
      ))
      continue

    if normalized notin ["nodestarted", "nodefinished", "nodefailed", "nodeskipped"]:
      continue
    if item.nodeId.len == 0:
      errors.add("node adapter event is missing nodeId")
      continue

    var observation = observations.getOrDefault(item.nodeId,
      NodeObservation(nodeId: item.nodeId, status: nsPending))

    if normalized == "nodestarted":
      observation.started = true
      observation.startedMs = item.timestampMs
      if item.timestampMs > 0 and (not hasBase or item.timestampMs < baseMs):
        baseMs = item.timestampMs
        hasBase = true
    else:
      let duration = max(0, item.durationMs)
      var finishMs = item.timestampMs
      if finishMs <= 0 and observation.started and observation.startedMs > 0:
        finishMs = observation.startedMs + duration
      elif finishMs <= 0:
        finishMs = fallbackClock + duration

      var startMs = observation.startedMs
      if not observation.started or startMs <= 0:
        if item.timestampMs > 0 and duration > 0:
          startMs = item.timestampMs - duration
        else:
          startMs = fallbackClock
        observation.started = true

      observation.finished = true
      observation.startedMs = startMs
      observation.finishedMs = finishMs
      observation.durationMs = max(0, finishMs - startMs)
      if observation.durationMs == 0 and duration > 0:
        observation.durationMs = duration
        observation.finishedMs = observation.startedMs + duration
      observation.status = item.terminalStatus()
      observation.retryCount = item.retryCount
      observation.errorKind = item.errorKind
      observation.message = item.message
      fallbackClock = max(fallbackClock, observation.finishedMs)

      if observation.startedMs > 0 and
          (not hasBase or observation.startedMs < baseMs):
        baseMs = observation.startedMs
        hasBase = true

    observations[item.nodeId] = observation

  result.plan = plan
  result.dryRun = plan.readyBatches()
  if not result.dryRun.ok:
    for error in result.dryRun.errors:
      errors.add(error)

  var timeline: seq[NodeRun] = @[]
  for _, item in observations:
    if not item.finished:
      continue
    let startRel = max(0, item.startedMs - baseMs)
    let finishRel = max(startRel, item.finishedMs - baseMs)
    timeline.add(NodeRun(
      nodeId: item.nodeId,
      title: plan.nodeTitle(item.nodeId),
      status: item.status,
      startedMs: startRel,
      finishedMs: finishRel,
      durationMs: item.durationMs,
      retries: item.retryCount,
      message: item.message
    ))
    if item.status == nsFailed:
      errors.add(if item.errorKind.len > 0: item.errorKind else: item.message)

  timeline.sort(proc(a, b: NodeRun): int =
    let byStart = cmp(a.startedMs, b.startedMs)
    if byStart != 0: byStart else: cmp(a.nodeId, b.nodeId))

  var totalMs = 0
  for item in timeline:
    totalMs = max(totalMs, item.finishedMs)

  result.run.timeline = timeline
  result.run.planId = plan.id
  result.run.variant = plan.variant
  result.run.ok = errors.len == 0
  result.run.totalMs = totalMs
  result.run.errors = errors
  result = result.complete()
  result = result.attachSurveyor()
  for item in explicitWaits:
    result.survey.waitInsights.add(item)
