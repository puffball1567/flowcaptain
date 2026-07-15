import std/[json, sequtils, strutils, unittest]

import flowcaptain

suite "investigation":
  test "builds node candidates from metadata and runtime signals":
    var plan = initCaptainPlan("billing-flow", "Billing Flow")
    plan.nodes.add(node("load-orders", "Load Orders", expectedMs = 120,
      fail = false, retries = 0,
      metadata = metadata([
        ("kind", "serviceMethod"),
        ("owner", "billing-platform"),
        ("department", "finance"),
        ("source", "laravel-adapter"),
        ("granularity", "coarse"),
        ("confidence", "0.9")
      ])))
    plan.nodes.add(node("price-orders", "Price Orders", expectedMs = 900,
      fail = false, retries = 2,
      metadata = metadata([("kind", "modelMethod")])) )
    plan.nodes.add(node("write-invoices", "Write Invoices", expectedMs = 240))
    plan.edges.add(edge("load-price", "load-orders", "price-orders"))
    plan.edges.add(edge("price-write", "price-orders", "write-invoices"))

    let outcome = plan.execute().complete().attachSurveyor()
    let report = outcome.investigationReport()

    check report.candidates.len == 3
    check report.candidates[0].kind == "serviceMethod"
    check report.candidates[0].owner == "billing-platform"
    check report.candidates[0].department == "finance"
    check report.candidates[0].confidence == 0.9
    check report.suggestions.len > 0
    check report.suggestions.mapIt(it.kind).join(" ").contains("retryInvestigation")
    check report.suggestions.mapIt(it.kind).join(" ").contains("granularityIncrease")

    let payload = report.toJson()
    check payload["schemaVersion"].getInt() == 1
    check payload["candidates"].len == 3
    check payload["suggestions"].len == report.suggestions.len

  test "exposes investigation through reports and public API":
    var plan = initCaptainPlan("approval-flow", "Approval Flow")
    plan.nodes.add(node("submit", "Submit", expectedMs = 40,
      fail = false, retries = 0,
      metadata = metadata([("kind", "businessStep"), ("department", "sales")])) )
    plan.nodes.add(node("manual-review", "Manual Review", expectedMs = 700))
    plan.edges.add(edge("submit-review", "submit", "manual-review"))

    let outcome = plan.execute().complete().attachSurveyor()
    let jsonPayload = investigationJson(outcome)
    check jsonPayload["flowId"].getStr() == "approval-flow"
    check jsonPayload["suggestions"].len > 0

    let comparison = compare(outcome, outcome)
    let output = artifacts(comparison)
    check output.reportMarkdown.contains("## Investigation guidance")
    check output.reportMarkdown.contains("Next investigation steps")
    check output.reportHtml.contains("Investigation Guidance")
