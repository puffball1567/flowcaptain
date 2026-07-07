# Dependency Notices

FlowCaptain is licensed under the Apache License 2.0. See `LICENSE`.

This file summarizes FlowBrigade Toolkit components and external software that
FlowCaptain directly depends on or integrates with in the public repository. It
is a release checklist aid, not legal advice. Verify exact license texts and
packaged artifacts before a tagged release or binary distribution.

## FlowBrigade Toolkit Components

These components are part of the FlowBrigade Toolkit family.

| Component | Use | License | Notes |
| --- | --- | --- | --- |
| FlowDependency | Flow graph and dependency model integration | Apache-2.0 | Intended toolkit component for graph structure. |
| FlowWorkRunner | Work execution integration | Apache-2.0 | Intended toolkit component for execution behavior. |
| FlowBrigade | Runtime control integration | Apache-2.0 | Intended toolkit component for retry, throttling, deadlines, and flow control. |
| FlowLogbook | Event and run record integration | Apache-2.0 | Intended toolkit component for run records and resume decisions. |
| FlowSurveyor | Flow analysis provider for reports | Apache-2.0 | Used to produce wait insights, parallelism opportunities, failure/retry impact, recommendations, and variant improvement/regression notes. |
| FlowGarage | Report and artifact bundle integration | Apache-2.0 | Intended toolkit component for report bundles and manifests. |

## External Dependencies

| Component | Use | License | Notes |
| --- | --- | --- | --- |
| Nim compiler and standard library | Build toolchain and standard library APIs | MIT | FlowCaptain is written in Nim and imports Nim standard library modules. |
| PHP runtime | Optional Laravel-compatible adapter smoke tests and examples | PHP License | The adapter itself has no Composer package dependency and is not required for Nim library use. |

## Release Checklist

Before a public release:

- confirm `flowcaptain.nimble` dependency declarations match this file;
- confirm FlowSurveyor's license and version before publishing a tagged
  FlowCaptain release;
- include required license texts when distributing compiled binaries,
  containers, or bundled source archives;
- keep this file updated when new FlowBrigade Toolkit components or external
  packages become direct dependencies.
