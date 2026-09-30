# Megascene supervision and retained prefixes

Issue #50 adds resource supervision to the static development runner. It does
not qualify benchmark, capacity, responsiveness, correctness or calibration
claims that still lack their required evidence. The accepted policies are
[limits and stopping](https://github.com/aivv73/bend-voxel/issues/39#issuecomment-5858595531)
and [measurement and reproduction](https://github.com/aivv73/bend-voxel/issues/42#issuecomment-5862953507).

## Invocation and campaign allowance

```sh
python3 scripts/megascene.py --case static --preset small --threads 6 \
  --resolution 1920x1080 --archive "$HOME/megascene-evidence" \
  --output build/megascene/supervised-static
```

The archive root owns the authoritative `campaign.json` and an exclusive
`campaign.lock`; attempt directories retain their prelaunch campaign snapshot. Reuse
that root for subsequent attempts and implementation tickets. The initial
allowance is 7,200 seconds of wall time, including generation, compilation,
validation, captures, controls, retries and time between invocations. Each
worker receives at most the remaining allowance. Build commands also respect
that remaining time. Opening a new output directory does not reset the campaign.
An admission/reference invocation can charge the same allowance with
`--campaign "$HOME/megascene-evidence"`.

A normally reported failed attempt retains its result and consumes allowance.
An interrupted or exhausted campaign requires an explicit
`--additional-allowance SECONDS` on a subsequent invocation. An abandoned active
lease also requires this declaration. Additions are retained in order; previous
attempts and charges remain. Time after exhaustion does not become funded work.
Do not select a different archive or declare an addition merely to bypass an
exhausted allowance. Monotonic time is used within a boot; persisted UTC and boot
identity conservatively account for a restart across boots. Changing tickets
has no effect on the allowance.

## Counters and policies

The monitor requests samples every 100 ms, including during startup and long
world/render operations. Evidence retains actual collection begin/end times,
source, scope, device, heap, process membership and observed gaps. Required
counter failures or data more than one second old stop the attempt. Sampled
maxima are observations, not exact peaks.

| Counter | Implementation and scope | Stop threshold |
| --- | --- | --- |
| Current RSS | Linux `/proc` process-tree membership and page residency, including the isolated worker process group | At least 20 GiB |
| Available RAM | `/proc/meminfo` `MemAvailable`, system wide | Below 6 GiB |
| Device free memory | NVML selected by Vulkan PCI bus identity, device wide | Below 768 MiB |
| Heap usage/budget | `VK_EXT_memory_budget` queried inside the worker process on an independent native monitor thread, each heap | Usage at least 90% of current budget |

The current required device monitor supports NVIDIA NVML on Linux. Missing
NVML, Vulkan budget/PCI capability, or an attribution mismatch is an explicit
monitoring failure. There is no fabricated zero or fallback resource pass.
[Heap usage is a process estimate](https://registry.khronos.org/VulkanSC/specs/1.0-extensions/man/html/VK_EXT_memory_budget.html);
[NVML free memory is device wide](https://docs.nvidia.com/deploy/nvml-api/api/group__nvmlDeviceQueries.html).
These quantities are never added to process residency or allocation ledger totals.

A short isolated preflight probe checks Vulkan capability, budgets and device
identity. Its heap usage is explicitly scoped to the probe. Host/device reserves
are checked before worker launch. The worker then starts its own heap monitor
and waits at a supervisor gate before generating the world. Only valid,
process-attributed heap and host/device samples release that gate. Renderer and
monitor device UUIDs must match. The monitor thread exists to provide required
coverage during blocking work; this is not a performance parallelism change.

Startup stops at 120 seconds without a usable frame. After startup, the
completion watchdog stops after 30 seconds without a completed frame/edit.
Logs and heartbeats do not reset it. The case stops at 300 seconds or the lower
explicit `--deadline`, and the campaign deadline may stop it sooner. The earliest
applicable deadline wins. [Performance v2](megascene-performance-v2.md) separately declares a 480-second cap for complete history validation at 120/21600; its timed workers keep the 300-second cap. An explicit smaller deadline and every other stopping condition remain effective. The separate 30-second interactive startup gate
remains a qualification concern, not the startup stop deadline.

## Allocation and reference evidence

All explicit `vkAllocateMemory`/`vkFreeMemory` calls pass through the ledger.
`allocations.jsonl` retains allocation identity, size, memory type, heap/device,
operation result, live/peak totals and heap live/peak totals. Failed calls have
separate `allocation_failed` records and never increase usage. Other failed
Vulkan operations retain their operation and result, including device loss.
The supervisor audits identity, free matching and totals. Allocation sizes
are exact application ledger amounts; driver/internal allocations, swapchain
storage and physical residency are different quantities.

`reference.shared` is a preallocated, bounded, append-only shared mapping.
Its capacity is the declared frame count plus startup and three records for
each of at most 120 actions. Slots are 1,024 bytes and never reused. The single IO-thread producer
copies a complete record, then publishes its sequence with a release atomic.
The supervisor reads with an acquire atomic, validates identity, sequence,
intervals and action scalars, and persists `reference.jsonl` during execution
and again after termination. A crash between slot commit and header update
does not lose the committed slot. The mapping is retained for recovery.

The static worker commits every frame through this path before detailed frame
logging. The same recorder accepts edit start, completed edit, and scalar action
acceptance/removal records; controlled tests exercise these records. Static has
no edits. Future replay/calibration modes must use this same path; their workload
implementation is not supplied by this issue. Capacity exhaustion, oversized or
damaged committed records, gaps and CPU/reference disagreement invalidate
completion. The full raw mapping remains even when only a prefix is readable.

## Persistence and termination

The supervisor executes archived runtime bytes. Detailed CPU records, heap and
allocation records, stdout and stderr are written directly into that durable
attempt directory. The supervisor drains host/device samples, syncs required
streams periodically, drains final pipe/shared records after worker termination,
and syncs final evidence. JSON snapshots use temporary files, fsync, atomic
replacement and directory fsync. Completed attempt summaries and campaign
progress are saved before another launch, including an optional capture.
Truncated tails stay at their original paths; partial monitor pipe bytes go to
`monitor.damaged`. They cannot count as samples. Reference persistence failure
retains the committed shared bytes and fails the attempt.

`supervision.json` records the precise termination cause, separate exit/signal,
resource sample gaps and observed extrema, audited allocation totals, reference
counts, completed frame/action prefix and evidence errors. `resources.jsonl`
keeps original heap sample identities/times alongside the supervisor sequence;
`heaps.jsonl` preserves the complete original worker stream. `invocation.json`
records the policy and shared capacity. CPU and reference prefixes are reported
separately if a worker dies between their commits.

Known reserve, deadline, monitoring or persistence stops take precedence over
the resulting termination signal. Explicit allocation errors, device loss,
unexplained crashes, worker errors, window closure and external supervisor
signals remain separate. A signal by itself never establishes memory exhaustion.
Stopping includes the worker's descendants/process group and both monitor
processes. A required resource or persistence failure cannot supply successful
schedule completion, even if a completed prefix survived.

## Verification

```sh
python3 -m unittest discover -s tests -p test_megascene_supervisor.py -v
MEGASCENE_VULKAN_TEST=1 python3 -m unittest discover -s tests -p test_megascene_static.py -v
make test
bend PROOF.bend
bend PROOF.bend --verdict
```

Controlled subprocess fixtures use the production supervision boundary and the
actual C shared commit function. Their manifests are synthetic and cannot enter
measured searches. They inject reserves, stale/missing/failed monitors, all
four deadline categories, external signals, crashes, failed allocations, device
loss, damaged tails, reference gaps/overflow/loss and a real failing `/dev/full`
persistence descriptor, without exhausting resources. A native driver-response
fixture checks actual allocation wrappers and exact identities/totals. The
Vulkan test verifies real completion, capture, archive relocation and a controlled
display failure. These are runtime/reference results; no unsafe or native
property is represented as formally proven.

See the [retained verification](validation/megascene-supervision/README.md) for
the complete static invocation, injected outcomes and regression logs.

## Persistence during complete picking replays

Issue #54's complete replay exposed synchronous `fsync` stalls that delayed
otherwise timely host and heap samples. The supervisor now performs durability
flushes on one I/O worker with at most one flush in flight. The normal 100 ms
request cadence, unbuffered append-only writes, non-reused committed slots and
resource freshness/reserve/deadline checks remain. A flush failure propagates
as a persistence failure; finalization waits for outstanding I/O and flushes
the final prefix before accepting the evidence. `supervision.json` records
`durability.mode` and whether the final barrier completed. Blocked-flush and
failed-flush fixtures cover this runtime boundary independently of picking.
