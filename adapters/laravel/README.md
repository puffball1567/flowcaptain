# FlowCaptain Laravel Adapter

Thin Laravel-compatible adapter for emitting FlowCaptain JSONL events from
Artisan commands, queue jobs, schedulers, and web-batch segments.

The adapter does not capture return values or payloads. It records timing,
status, retry count, coarse error kind, and optional short tags.

## Install Locally

During development from this repository:

```bash
cd adapters/laravel
composer test
```

In a Laravel application, this package can be added later as a path repository
or as a published Composer package.

## Basic Usage

```php
use FlowCaptain\LaravelAdapter\FlowCaptainRun;

$run = FlowCaptainRun::start(
    flowId: 'billing',
    runId: 'billing-' . date('Ymd-His'),
    path: storage_path('flowcaptain/billing.jsonl'),
    variantId: 'A',
);

$users = $run->measure('load-users', fn () => loadUsers());
$invoices = $run->measure('calculate', fn () => calculateInvoices($users));
$run->measure('send-mail', fn () => sendMails($invoices));

$run->finish();
```

## Queue Job

```php
public function handle(): void
{
    $run = FlowCaptainRun::start('billing', (string) $this->job->getJobId(),
        storage_path('flowcaptain/billing.jsonl'));

    $run->measure('load-users', fn () => $this->loadUsers());
    $run->measure('calculate', fn () => $this->calculate());
    $run->finish();
}
```

## Generate A Report

Use the generated JSONL with the FlowCaptain CLI after installing FlowCaptain:

```bash
flowcaptain_event_report \
  --plan examples/billing_plan.json \
  --events reports/laravel-adapter/billing_events.jsonl \
  --out reports/laravel-adapter-report \
  --run-id laravel-run-1
```

When working from this repository without installing the package, run the
repository example:

```bash
nimble laravelAdapterExample
```

Open:

```text
reports/laravel-adapter-report/captain-report.html
```

## Production Notes

- Keep this adapter in minimal mode for always-on jobs.
- Do not put request bodies, model payloads, personal data, tokens, or SQL
  parameters in tags or messages.
- Prefer stable node ids such as `load-users`, `calculate`, and `send-mail`.
- Generate HTML reports out of band rather than during every production run.
