# FlowCaptain Methodology

FlowCaptain is intended for flow investigation, not only flow execution. The
core loop is: hear, model, measure, analyze, report, improve, and measure again.

## Standard Cycle

1. Hearing: interview operators, developers, analysts, and managers to identify
   business steps, system boundaries, manual work, queues, data stores, and
   known pain points.
2. Initial graph: create a coarse node-and-arrow graph from the hearing result.
   The first graph is a working hypothesis, not a final answer.
3. Measurement: connect adapter events, logs, database records, queue records,
   manual timestamps, or imported metrics to the graph.
4. Analysis: inspect duration, wait, retry, failure, throughput, first-pass
   yield, defect rate, and critical-path impact.
5. Reporting: explain which node or arrow affects the whole flow, which slow
   point has limited impact, and which point needs deeper measurement.
6. Feedback: collect comments from the people who run or depend on the flow.
7. Refinement: split unclear nodes, merge noisy nodes, add ownership metadata,
   or add a better data source.
8. Next run: measure again and compare whether the whole flow improved.

## What Makes This Different

A slow query, slow method, or slow job is not automatically the business
bottleneck. FlowCaptain places technical and operational signals onto a graph so
that analysts can see whether a local problem affects the whole flow.

## Investigation Levels

- Coarse: departments, business steps, external systems, or scheduled batches.
- Normal: services, jobs, handlers, approval steps, or data handoffs.
- Detailed: methods, query groups, table updates, API calls, retry causes, or
  manual substeps.

Start coarse. Increase granularity only where the data or field feedback says
the current node hides important work.
