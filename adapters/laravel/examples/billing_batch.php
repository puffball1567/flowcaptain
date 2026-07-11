<?php

declare(strict_types=1);

require __DIR__ . '/../src/FlowCaptainRun.php';

use FlowCaptain\LaravelAdapter\FlowCaptainRun;

$eventPath = __DIR__ . '/../../../reports/laravel-adapter/billing_events.jsonl';
if (is_file($eventPath)) {
    unlink($eventPath);
}

$run = FlowCaptainRun::start('billing', 'laravel-run-1', $eventPath, 'A');

$users = $run->measure('load-users', static function (): array {
    usleep(120_000);
    return [101, 102, 103];
});

$run->nodeStarted('calculate');
$run->nodeStarted('render');

usleep(410_000);
$run->nodeFinished('render', 410);

usleep(440_000);
$run->nodeFinished('calculate', 850, retryCount: 1);
$run->edgeWaitObserved('render-mail', 440, 'render finished before calculate');

$run->measure('send-mail', static function () use ($users): int {
    usleep(90_000);
    return count($users);
});

$run->finish();

echo $eventPath . PHP_EOL;
