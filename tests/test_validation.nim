import std/unittest

import flowcaptain

suite "validation":
  test "accepts a valid plan":
    var plan = initCaptainPlan("daily-report", "Daily")
    plan.nodes.add(node("extract", "Extract"))
    plan.nodes.add(node("publish", "Publish"))
    plan.edges.add(edge("extract-publish", "extract", "publish"))
    let checked = plan.validate()
    check checked.ok

  test "rejects invalid references and duplicate ids":
    var plan = initCaptainPlan("bad plan", "")
    plan.nodes.add(node("same", "One"))
    plan.nodes.add(node("same", "Two"))
    plan.edges.add(edge("bad-edge", "same", "missing"))
    let checked = plan.validate()
    check not checked.ok
    check checked.errors.len >= 3

  test "rejects negative duration and retry values":
    var plan = initCaptainPlan("daily", "Daily")
    plan.nodes.add(node("bad", "Bad", plannedMs = -1, retries = -1))
    let checked = plan.validate()
    check not checked.ok
    check checked.errors.len >= 2
