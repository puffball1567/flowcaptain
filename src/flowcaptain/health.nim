import ./types

proc clamp(value, low, high: float): float =
  if value < low:
    low
  elif value > high:
    high
  else:
    value

proc ratio(part, total: int): float =
  if total <= 0:
    0.0
  else:
    part.float / total.float

proc totalWorkMs(outcome: CaptainOutcome): int =
  for item in outcome.run.timeline:
    result.inc item.durationMs

proc totalWaitMs(outcome: CaptainOutcome): int =
  for item in outcome.survey.waitInsights:
    result.inc item.totalWaitMs

proc grade(score: float): string =
  if score >= 90.0: "excellent"
  elif score >= 75.0: "good"
  elif score >= 60.0: "watch"
  else: "poor"

proc health*(outcome: CaptainOutcome): FlowHealth =
  let totalNodes = outcome.run.timeline.len
  var succeeded = 0
  var failed = 0
  var skipped = 0
  var retries = 0
  for item in outcome.run.timeline:
    case item.status
    of nsSucceeded: succeeded.inc
    of nsFailed: failed.inc
    of nsSkipped: skipped.inc
    of nsPending: discard
    retries.inc item.retries

  let workMs = outcome.totalWorkMs()
  let waitMs = outcome.totalWaitMs()
  let successRate = ratio(succeeded, totalNodes)
  let failureRate = ratio(failed + skipped, totalNodes)
  let retryRate = ratio(retries, max(totalNodes, 1))
  let waitShare = ratio(waitMs, max(workMs + waitMs, 1))
  let criticalPathShare = ratio(outcome.analysis.criticalPathMs, max(workMs, 1))
  let concurrencyFactor = ratio(workMs, max(outcome.run.totalMs, 1))

  var score = 100.0
  score -= failureRate * 45.0
  score -= min(retryRate, 2.0) * 10.0
  score -= min(waitShare, 1.0) * 20.0
  if criticalPathShare > 0.80:
    score -= (criticalPathShare - 0.80) * 25.0
  if concurrencyFactor > 0.0 and concurrencyFactor < 1.0:
    score -= (1.0 - concurrencyFactor) * 10.0
  score = score.clamp(0.0, 100.0)

  var reasons: seq[string] = @[]
  if failed > 0:
    reasons.add($failed & " failed nodes were observed")
  if skipped > 0:
    reasons.add($skipped & " skipped nodes were observed")
  if retries > 0:
    reasons.add($retries & " retries were observed")
  if waitShare >= 0.20:
    reasons.add("edge waits account for " & $(waitShare * 100.0) & "% of observed work plus wait")
  if criticalPathShare >= 0.80:
    reasons.add("critical path dominates observed work")
  if reasons.len == 0:
    reasons.add("no major reliability or flow-shape issues were detected")

  FlowHealth(score: score, grade: score.grade(), successRate: successRate,
             failureRate: failureRate, retryRate: retryRate,
             waitShare: waitShare, criticalPathShare: criticalPathShare,
             concurrencyFactor: concurrencyFactor, reasons: reasons)
