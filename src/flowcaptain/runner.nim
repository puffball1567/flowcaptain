import std/tables

import ./types
import ./planner

proc byId(plan: CaptainPlan): Table[string, CaptainNode] =
  for item in plan.nodes:
    result[item.id] = item

proc requiredSources(plan: CaptainPlan): Table[string, seq[string]] =
  for item in plan.nodes:
    result[item.id] = @[]
  for item in plan.edges:
    if item.kind == ekRequired and item.waitOn:
      result[item.toNode].add(item.fromNode)

proc run*(plan: CaptainPlan): CaptainRun =
  let dry = plan.readyBatches()
  if not dry.ok:
    return CaptainRun(planId: plan.id, variant: plan.variant, ok: false,
                      totalMs: 0, timeline: @[], errors: dry.errors)

  let nodes = plan.byId()
  let required = plan.requiredSources()
  var status = initTable[string, NodeStatus]()
  var clock = 0
  var timeline: seq[NodeRun] = @[]
  var errors: seq[string] = @[]

  for batch in dry.batches:
    var maxDuration = 0
    var batchRuns: seq[NodeRun] = @[]
    for id in batch:
      let item = nodes[id]
      var blocked = false
      for source in required[id]:
        if status.getOrDefault(source, nsPending) != nsSucceeded:
          blocked = true

      var run = NodeRun(nodeId: id, title: item.title, startedMs: clock,
                        finishedMs: clock, durationMs: 0, retries: 0,
                        message: "")
      if blocked:
        run.status = nsSkipped
        run.message = "required upstream node did not succeed"
      elif item.fail:
        run.status = nsFailed
        run.durationMs = item.plannedMs
        run.retries = item.retries
        run.finishedMs = clock + run.durationMs
        run.message = "simulated failure"
        errors.add("node failed: " & id)
      else:
        run.status = nsSucceeded
        run.durationMs = item.plannedMs
        run.retries = item.retries
        run.finishedMs = clock + run.durationMs
        run.message = "simulated success"

      status[id] = run.status
      if run.durationMs > maxDuration:
        maxDuration = run.durationMs
      batchRuns.add(run)

    timeline.add(batchRuns)
    clock = clock + maxDuration

  CaptainRun(planId: plan.id, variant: plan.variant, ok: errors.len == 0,
             totalMs: clock, timeline: timeline, errors: errors)

proc execute*(plan: CaptainPlan): CaptainOutcome =
  let dry = plan.readyBatches()
  let runResult = plan.run()
  CaptainOutcome(plan: plan, dryRun: dry, run: runResult)
