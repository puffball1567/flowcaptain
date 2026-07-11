<?php

declare(strict_types=1);

require __DIR__ . '/../src/FlowCaptainRun.php';

use FlowCaptain\LaravelAdapter\FlowCaptainRun;

$path = sys_get_temp_dir() . '/flowcaptain-laravel-adapter-test/events.jsonl';
if (is_file($path)) {
    unlink($path);
}

$run = FlowCaptainRun::start('billing', 'run-1', $path, 'A');

$users = $run->measure('load-users', static fn (): array => [1, 2, 3]);
if ($users !== [1, 2, 3]) {
    throw new RuntimeException('measure must return callback value');
}

$run->measure('calculate', static fn (): int => 42, ['queue' => 'billing']);
$run->edgeWaitObserved('render-mail', 25, 'render finished first');
$run->nodeSkipped('send-mail', 'disabled in test');
$run->finish();

$lines = array_values(array_filter(explode("\n", trim((string) file_get_contents($path)))));
if (count($lines) !== 8) {
    throw new RuntimeException('unexpected event count: ' . count($lines));
}

$events = array_map(static fn (string $line): array => json_decode($line, true, flags: JSON_THROW_ON_ERROR), $lines);

if ($events[0]['eventType'] !== 'runStarted') {
    throw new RuntimeException('first event must be runStarted');
}
if ($events[2]['eventType'] !== 'nodeFinished' || $events[2]['nodeId'] !== 'load-users') {
    throw new RuntimeException('load-users finish event missing');
}
if ($events[4]['tags']['queue'] !== 'billing') {
    throw new RuntimeException('tags were not emitted');
}
if ($events[5]['eventType'] !== 'edgeWaitObserved' || $events[5]['durationMs'] !== 25) {
    throw new RuntimeException('edge wait event missing');
}

echo "Laravel adapter test passed\n";
