version       = "0.1.0"
author        = "flowcaptain contributors"
description   = "Top-level orchestration and reporting layer for FlowBrigade Toolkit flows."
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
skipDirs      = @[
  ".github",
  "benchmarks",
  "docs",
  "examples",
  "reports",
  "tests"
]

requires "nim >= 2.2.0"

let flowToolkitPath = "-p:deps/flowdependency/src -p:deps/flowworkrunner/src " &
                      "-p:deps/flowbrigade/src -p:deps/flowlogbook/src " &
                      "-p:deps/flowsurveyor/src -p:deps/flowgarage/src"

task test, "Run the test suite":
  exec "nim r --nimcache:/tmp/flowcaptain-test-nimcache -p:src " & flowToolkitPath & " tests/all.nim"

task examples, "Run examples and generate inspectable reports":
  exec "nim r --nimcache:/tmp/flowcaptain-nimcache -p:src " & flowToolkitPath & " examples/daily_report.nim"

task bench, "Run basic local benchmarks":
  exec "nim r -d:release --nimcache:/tmp/flowcaptain-bench-nimcache -p:src " & flowToolkitPath & " benchmarks/basic_captain.nim"
