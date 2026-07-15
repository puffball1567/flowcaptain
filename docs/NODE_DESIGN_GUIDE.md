# Node Design Guide

A FlowCaptain node should represent a unit that someone can discuss, measure,
and improve. It does not have to be executable by FlowCaptain.

## Good Node Candidates

- Business process step
- Department handoff
- Service method
- Model method
- Controller, handler, command, or queue job
- Database table update or query group
- External API call
- File import or export
- Manual review, approval, or rework step
- Existing log event or OpenTelemetry span

## Useful Metadata

FlowCaptain keeps node metadata open-ended. The following keys are useful for
investigation reports and GUI tooling:

- `kind`: `businessStep`, `serviceMethod`, `modelMethod`, `databaseTable`,
  `queueJob`, `externalApi`, `manualWork`, `departmentHandoff`, or another
  project-specific value.
- `owner`: team or person responsible for follow-up.
- `department`: business department or operational area.
- `source`: where the node was discovered, such as `hearing`, `laravel-adapter`,
  `otel`, `job-log`, or `manual-import`.
- `granularity`: `coarse`, `normal`, or `detailed`.
- `confidence`: value from `0.0` to `1.0` describing how reliable the mapping is.

## Arrow Design

Use arrows for actual dependency or handoff. An arrow can mean a system call, a
queue handoff, a manual approval, a data dependency, or a business sequence.
`waitOn` means the downstream node should not be treated as ready until the
arrow is satisfied.

## Refinement Rules

- Split a node when it is slow, unstable, disputed by field feedback, or too
  broad to assign an owner.
- Merge nodes when they are too noisy, always move together, or cannot produce
  separate decisions.
- Add metadata before adding more nodes when ownership or department context is
  missing.
- Keep the previous graph variant so that improvement can be compared.
