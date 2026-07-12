version       = "0.1.1"
author        = "flowcaptain contributors"
description   = "Top-level orchestration and reporting layer for FlowBrigade Toolkit flows."
license       = "Apache-2.0"
srcDir        = "src"
bin           = @["flowcaptain_event_report"]
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
requires "flowbrigade >= 0.4.1"
requires "https://github.com/puffball1567/flowdependency >= 0.3.0"
requires "https://github.com/puffball1567/flowworkrunner >= 0.2.0"
requires "https://github.com/puffball1567/flowlogbook >= 0.2.0"
requires "https://github.com/puffball1567/flowsurveyor >= 0.2.0"
requires "https://github.com/puffball1567/flowgarage >= 0.1.0"

let flowToolkitPath = "-p:deps/flowdependency/src -p:deps/flowworkrunner/src " &
                      "-p:deps/flowbrigade/src -p:deps/flowlogbook/src " &
                      "-p:deps/flowsurveyor/src -p:deps/flowgarage/src"

task test, "Run the test suite":
  exec "nim r --nimcache:/tmp/flowcaptain-test-nimcache -p:src " & flowToolkitPath & " tests/all.nim"

task leak, "Run the ARC leak probe under Valgrind":
  exec "nim c -d:release --nimcache:/tmp/flowcaptain-leak-nimcache -p:src " & flowToolkitPath & " --out:/tmp/flowcaptain-leak-probe tests/leak_probe.nim"
  exec "valgrind --leak-check=full --show-leak-kinds=definite,indirect --errors-for-leak-kinds=definite,indirect --error-exitcode=99 /tmp/flowcaptain-leak-probe"

task examples, "Run examples and generate inspectable reports":
  exec "nim r --nimcache:/tmp/flowcaptain-nimcache -p:src " & flowToolkitPath & " examples/daily_report.nim"

task eventReportExample, "Generate reports from adapter event JSONL":
  exec "nim r --nimcache:/tmp/flowcaptain-cli-nimcache -p:src " & flowToolkitPath & " src/flowcaptain_event_report.nim --plan examples/billing_plan.json --events examples/billing_events.jsonl --out reports/adapter --run-id run-1"

task laravelAdapterExample, "Run the Laravel adapter example and generate a FlowCaptain report":
  exec "php adapters/laravel/examples/billing_batch.php"
  exec "nim r --nimcache:/tmp/flowcaptain-cli-nimcache -p:src " & flowToolkitPath & " src/flowcaptain_event_report.nim --plan examples/billing_plan.json --events reports/laravel-adapter/billing_events.jsonl --out reports/laravel-adapter-report --run-id laravel-run-1"

task bench, "Run basic local benchmarks":
  exec "nim r -d:release --nimcache:/tmp/flowcaptain-bench-nimcache -p:src " & flowToolkitPath & " benchmarks/basic_captain.nim"
