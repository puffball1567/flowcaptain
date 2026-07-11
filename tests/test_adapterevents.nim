import std/[strutils, unittest]

import flowcaptain

suite "adapter events":
  test "round-trips plan JSON for CLI adapter reports":
    var plan = initCaptainPlan("billing", "Billing", variant = "A")
    plan.nodes.add(node("load-users", "Load Users", plannedMs = 120))
    plan.nodes.add(node("calculate", "Calculate Invoices", plannedMs = 850))
    plan.edges.add(edge("load-calculate", "load-users", "calculate"))

    let parsed = plan.toJson().planFromJson()

    check parsed.id == "billing"
    check parsed.variant == "A"
    check parsed.nodes.len == 2
    check parsed.nodes[1].plannedMs == 850
    check parsed.edges.len == 1
    check parsed.edges[0].waitOn

  test "round-trips framework adapter JSONL":
    let events = @[
      adapterEvent("runStarted", "billing", "run-1", variantId = "A"),
      adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
        nodeId = "load-users", timestampMs = 10, durationMs = 120,
        status = nsSucceeded),
      adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
        nodeId = "calculate", timestampMs = 20, durationMs = 850,
        status = nsSucceeded, retryCount = 1),
      adapterEvent("runFinished", "billing", "run-1", variantId = "A",
        status = nsSucceeded)
    ]

    let lines = events.adapterEventsJsonLines()
    check lines.splitLines().len == events.len
    check lines.contains("\"eventType\":\"nodeFinished\"")

    let parsed = lines.parseAdapterEventsJsonLines()
    check parsed.len == events.len
    check parsed[2].nodeId == "calculate"
    check parsed[2].durationMs == 850
    check parsed[2].retryCount == 1

  test "builds an analyzable outcome from adapter events":
    var plan = initCaptainPlan("billing", "Billing", variant = "A")
    plan.nodes.add(node("load-users", "Load Users"))
    plan.nodes.add(node("calculate", "Calculate Invoices"))
    plan.nodes.add(node("render", "Render Invoices"))
    plan.nodes.add(node("send-mail", "Send Mail"))
    plan.edges.add(edge("load-calculate", "load-users", "calculate"))
    plan.edges.add(edge("load-render", "load-users", "render"))
    plan.edges.add(edge("calculate-mail", "calculate", "send-mail"))
    plan.edges.add(edge("render-mail", "render", "send-mail"))

    let events = @[
      adapterEvent("runStarted", "billing", "run-1", variantId = "A",
        timestampMs = 1_000),
      adapterEvent("nodeStarted", "billing", "run-1", variantId = "A",
        nodeId = "load-users", timestampMs = 1_000),
      adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
        nodeId = "load-users", timestampMs = 1_120, durationMs = 120,
        status = nsSucceeded),
      adapterEvent("nodeStarted", "billing", "run-1", variantId = "A",
        nodeId = "calculate", timestampMs = 1_120),
      adapterEvent("nodeStarted", "billing", "run-1", variantId = "A",
        nodeId = "render", timestampMs = 1_120),
      adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
        nodeId = "calculate", timestampMs = 1_970, durationMs = 850,
        status = nsSucceeded),
      adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
        nodeId = "render", timestampMs = 1_530, durationMs = 410,
        status = nsSucceeded),
      adapterEvent("edgeWaitObserved", "billing", "run-1", variantId = "A",
        edgeId = "render-mail", timestampMs = 1_970, durationMs = 440,
        message = "render finished before calculate"),
      adapterEvent("nodeStarted", "billing", "run-1", variantId = "A",
        nodeId = "send-mail", timestampMs = 1_970),
      adapterEvent("nodeFinished", "billing", "run-1", variantId = "A",
        nodeId = "send-mail", timestampMs = 2_060, durationMs = 90,
        status = nsSucceeded),
      adapterEvent("runFinished", "billing", "run-1", variantId = "A",
        timestampMs = 2_060, status = nsSucceeded)
    ]

    let outcome = plan.outcomeFromAdapterEvents(events)

    check outcome.run.ok
    check outcome.run.timeline.len == 4
    check outcome.run.totalMs == 1060
    check outcome.analysis.slowestNode == "calculate"
    check outcome.analysis.criticalPath == @[
      "load-users",
      "calculate",
      "send-mail"
    ]
    check outcome.run.timeline[1].startedMs == outcome.run.timeline[2].startedMs
    check outcome.survey.waitInsights.len > 0

  test "rejects oversized adapter event lines":
    let tooLarge = repeat("x", MaxAdapterEventLineBytes + 1)

    expect ValueError:
      discard tooLarge.parseAdapterEventsJsonLines()
