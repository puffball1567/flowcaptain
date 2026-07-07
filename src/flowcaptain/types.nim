import std/[tables, times]

type
  NodeStatus* = enum
    nsPending, nsSucceeded, nsFailed, nsSkipped

  EdgeKind* = enum
    ekRequired, ekOptional

  CaptainNode* = object
    id*: string
    title*: string
    plannedMs*: int
    fail*: bool
    retries*: int
    metadata*: OrderedTable[string, string]

  CaptainEdge* = object
    id*: string
    fromNode*: string
    toNode*: string
    kind*: EdgeKind
    waitOn*: bool

  CaptainPlan* = object
    id*: string
    title*: string
    variant*: string
    nodes*: seq[CaptainNode]
    edges*: seq[CaptainEdge]
    metadata*: OrderedTable[string, string]

  ValidationResult* = object
    ok*: bool
    errors*: seq[string]

  DryRun* = object
    ok*: bool
    batches*: seq[seq[string]]
    errors*: seq[string]

  NodeRun* = object
    nodeId*: string
    title*: string
    status*: NodeStatus
    startedMs*: int
    finishedMs*: int
    durationMs*: int
    retries*: int
    message*: string

  CaptainRun* = object
    planId*: string
    variant*: string
    ok*: bool
    totalMs*: int
    timeline*: seq[NodeRun]
    errors*: seq[string]

  CaptainAnalysis* = object
    criticalPath*: seq[string]
    criticalPathMs*: int
    slowestNode*: string
    slowestNodeMs*: int
    failedNodes*: seq[string]
    retryCount*: int
    recommendation*: string

  CaptainWaitInsight* = object
    edgeId*: string
    fromNode*: string
    toNode*: string
    blockedCount*: int
    totalWaitMs*: int
    averageWaitMs*: float
    reason*: string

  CaptainParallelismOpportunity* = object
    nodeId*: string
    fanIn*: int
    fanOut*: int
    observedDurationMs*: int
    onCriticalPath*: bool
    score*: float
    reason*: string

  CaptainFailureImpact* = object
    targetId*: string
    kind*: string
    failureCount*: int
    retryCount*: int
    failedDurationMs*: int
    retryDurationMs*: int
    score*: float
    reason*: string

  CaptainSurveyInsights* = object
    waitInsights*: seq[CaptainWaitInsight]
    parallelismOpportunities*: seq[CaptainParallelismOpportunity]
    failureImpacts*: seq[CaptainFailureImpact]
    recommendations*: seq[string]

  CaptainOutcome* = object
    plan*: CaptainPlan
    dryRun*: DryRun
    run*: CaptainRun
    analysis*: CaptainAnalysis
    survey*: CaptainSurveyInsights

  VariantComparison* = object
    baseline*: CaptainOutcome
    candidate*: CaptainOutcome
    deltaMs*: int
    betterVariant*: string
    summary*: string
    surveySummary*: string
    improvements*: seq[string]
    regressions*: seq[string]

  CaptainArtifacts* = object
    reportMarkdown*: string
    reportHtml*: string
    flowMermaid*: string
    structureMermaid*: string
    comparisonMermaid*: string
    manifestJson*: string

  CaptainMetricEvent* = object
    schemaVersion*: Natural
    kind*: string
    flowId*: string
    runId*: string
    variantId*: string
    nodeId*: string
    edgeId*: string
    metricName*: string
    metricValue*: float
    unit*: string
    tags*: OrderedTable[string, string]
    message*: string

  CaptainAdapterEvent* = object
    schemaVersion*: Natural
    eventType*: string
    flowId*: string
    runId*: string
    variantId*: string
    nodeId*: string
    edgeId*: string
    timestampMs*: int
    durationMs*: int
    status*: NodeStatus
    retryCount*: int
    errorKind*: string
    message*: string
    tags*: OrderedTable[string, string]

proc metadata*(pairs: openArray[(string, string)]): OrderedTable[string, string] =
  result = initOrderedTable[string, string]()
  for pair in pairs:
    result[pair[0]] = pair[1]

proc nowIso*(): string =
  now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc node*(id, title: string; plannedMs = 1; fail = false; retries = 0): CaptainNode =
  CaptainNode(id: id, title: title, plannedMs: plannedMs, fail: fail,
              retries: retries, metadata: initOrderedTable[string, string]())

proc node*(id, title: string; plannedMs: int; fail: bool; retries: int;
           metadata: OrderedTable[string, string]): CaptainNode =
  CaptainNode(id: id, title: title, plannedMs: plannedMs, fail: fail,
              retries: retries, metadata: metadata)

proc edge*(id, fromNode, toNode: string; kind = ekRequired;
           waitOn = true): CaptainEdge =
  CaptainEdge(id: id, fromNode: fromNode, toNode: toNode, kind: kind,
              waitOn: waitOn)

proc initCaptainPlan*(id, title: string; variant = "A"): CaptainPlan =
  CaptainPlan(id: id, title: title, variant: variant, nodes: @[], edges: @[],
              metadata: initOrderedTable[string, string]())

proc validationOk*(): ValidationResult =
  ValidationResult(ok: true, errors: @[])

proc validationFailure*(errors: seq[string]): ValidationResult =
  ValidationResult(ok: false, errors: errors)
