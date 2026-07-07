<?php

declare(strict_types=1);

namespace FlowCaptain\LaravelAdapter;

use Throwable;

final class FlowCaptainRun
{
    private string $flowId;
    private string $runId;
    private string $variantId;
    private string $path;
    /** @var resource|null */
    private $handle = null;

    /** @var array<string, int> */
    private array $starts = [];

    private function __construct(string $flowId, string $runId, string $variantId, string $path)
    {
        $this->flowId = self::requireId($flowId, 'flowId');
        $this->runId = self::requireId($runId, 'runId');
        $this->variantId = $variantId === '' ? 'A' : $variantId;
        $this->path = $path;

        $directory = dirname($path);
        if (!is_dir($directory) && !mkdir($directory, 0775, true) && !is_dir($directory)) {
            throw new \RuntimeException('failed to create FlowCaptain event directory: ' . $directory);
        }

        $this->handle = fopen($path, 'ab');
        if ($this->handle === false) {
            $this->handle = null;
            throw new \RuntimeException('failed to open FlowCaptain event log: ' . $path);
        }
    }

    public static function start(string $flowId, string $runId, string $path, string $variantId = 'A'): self
    {
        $run = new self($flowId, $runId, $variantId, $path);
        $run->emit('runStarted', status: 'pending');
        return $run;
    }

    /**
     * Measures a batch, command, queue, scheduler, service, or repository segment.
     *
     * Return values are passed through to the caller and are never serialized.
     *
     * @template T
     * @param callable():T $callback
     * @return T
     */
    public function measure(string $nodeId, callable $callback, array $tags = []): mixed
    {
        $this->nodeStarted($nodeId, $tags);
        $started = self::nowMs();
        try {
            $value = $callback();
            $this->nodeFinished($nodeId, self::nowMs() - $started, 'succeeded', 0, '', '', $tags);
            return $value;
        } catch (Throwable $error) {
            $this->nodeFailed($nodeId, self::nowMs() - $started, self::errorKind($error), $tags);
            throw $error;
        }
    }

    public function nodeStarted(string $nodeId, array $tags = []): void
    {
        $nodeId = self::requireId($nodeId, 'nodeId');
        $this->starts[$nodeId] = self::nowMs();
        $this->emit('nodeStarted', nodeId: $nodeId, status: 'pending', tags: $tags);
    }

    public function nodeFinished(
        string $nodeId,
        int $durationMs = 0,
        string $status = 'succeeded',
        int $retryCount = 0,
        string $message = '',
        string $errorKind = '',
        array $tags = []
    ): void {
        $nodeId = self::requireId($nodeId, 'nodeId');
        if ($durationMs <= 0 && isset($this->starts[$nodeId])) {
            $durationMs = self::nowMs() - $this->starts[$nodeId];
        }
        $this->emit(
            'nodeFinished',
            nodeId: $nodeId,
            durationMs: max(0, $durationMs),
            status: $status,
            retryCount: $retryCount,
            errorKind: $errorKind,
            message: $message,
            tags: $tags
        );
    }

    public function nodeFailed(string $nodeId, int $durationMs = 0, string $errorKind = 'error', array $tags = []): void
    {
        $nodeId = self::requireId($nodeId, 'nodeId');
        if ($durationMs <= 0 && isset($this->starts[$nodeId])) {
            $durationMs = self::nowMs() - $this->starts[$nodeId];
        }
        $this->emit(
            'nodeFailed',
            nodeId: $nodeId,
            durationMs: max(0, $durationMs),
            status: 'failed',
            errorKind: $errorKind,
            tags: $tags
        );
    }

    public function nodeSkipped(string $nodeId, string $message = '', array $tags = []): void
    {
        $this->emit('nodeSkipped', nodeId: self::requireId($nodeId, 'nodeId'), status: 'skipped', message: $message, tags: $tags);
    }

    public function edgeWaitObserved(string $edgeId, int $durationMs, string $message = '', array $tags = []): void
    {
        $this->emit(
            'edgeWaitObserved',
            edgeId: self::requireId($edgeId, 'edgeId'),
            durationMs: max(0, $durationMs),
            status: 'succeeded',
            message: $message,
            tags: $tags
        );
    }

    public function finish(string $status = 'succeeded'): void
    {
        $this->emit('runFinished', status: $status);
        if (is_resource($this->handle)) {
            fflush($this->handle);
            fclose($this->handle);
        }
        $this->handle = null;
    }

    private function emit(
        string $eventType,
        string $nodeId = '',
        string $edgeId = '',
        int $durationMs = 0,
        string $status = 'pending',
        int $retryCount = 0,
        string $errorKind = '',
        string $message = '',
        array $tags = []
    ): void {
        if (!is_resource($this->handle)) {
            throw new \RuntimeException('FlowCaptain event log is closed');
        }

        $event = [
            'schemaVersion' => 1,
            'eventType' => $eventType,
            'flowId' => $this->flowId,
            'runId' => $this->runId,
            'variantId' => $this->variantId,
            'nodeId' => $nodeId,
            'edgeId' => $edgeId,
            'timestampMs' => self::nowMs(),
            'durationMs' => max(0, $durationMs),
            'status' => $status,
            'retryCount' => max(0, $retryCount),
            'errorKind' => $errorKind,
            'message' => self::sanitizeMessage($message),
            'tags' => (object) self::sanitizeTags($tags),
        ];

        fwrite($this->handle, json_encode($event, JSON_UNESCAPED_SLASHES) . "\n");
    }

    private static function nowMs(): int
    {
        return (int) floor(microtime(true) * 1000);
    }

    private static function requireId(string $value, string $label): string
    {
        $value = trim($value);
        if ($value === '') {
            throw new \InvalidArgumentException($label . ' is required');
        }
        if (strlen($value) > 160) {
            throw new \InvalidArgumentException($label . ' is too long');
        }
        if (!preg_match('/^[A-Za-z0-9_.:-]+$/', $value)) {
            throw new \InvalidArgumentException($label . ' contains unsupported characters');
        }
        return $value;
    }

    private static function sanitizeMessage(string $message): string
    {
        $message = str_replace(["\r", "\n"], ' ', $message);
        return substr($message, 0, 500);
    }

    private static function sanitizeTags(array $tags): array
    {
        $result = [];
        foreach ($tags as $key => $value) {
            if (!is_scalar($value) && $value !== null) {
                continue;
            }
            $cleanKey = preg_replace('/[^A-Za-z0-9_.:-]/', '_', (string) $key);
            if ($cleanKey === '') {
                continue;
            }
            $result[$cleanKey] = substr((string) $value, 0, 160);
        }
        return $result;
    }

    private static function errorKind(Throwable $error): string
    {
        $class = get_class($error);
        $base = strrchr($class, '\\');
        return $base === false ? $class : substr($base, 1);
    }
}
