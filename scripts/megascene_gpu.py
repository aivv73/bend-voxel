"""Validate persisted GPU evidence independently of the native timestamp resolver."""
import math
import re
import struct
from fractions import Fraction

from megascene_inventory import SCHEMA, integer, read_json, require

SCOPE = "submitted_frame_top_to_bottom"
STATES = {"measured", "unsupported", "disabled", "not_ready", "not_executed", "incomplete", "collection_failure"}


def u64(value):
    result = integer(value)
    require(result <= 2**64-1, "unsigned 64-bit value overflow")
    return result


def metadata(record):
    require(record["scope"] == SCOPE, "unknown GPU interval scope")
    encoded = record["period_bits"]
    require(isinstance(encoded, str) and re.fullmatch(r"0x[0-9a-f]{8}", encoded), "invalid period bits")
    period = struct.unpack(">f", bytes.fromhex(encoded[2:]))[0]
    require(record["period_ns"] == (period if math.isfinite(period) else None) and
            (record["period_ns"] is None or type(record["period_ns"]) in (int, float)), "timestamp period mismatch")
    return period, u64(record["valid_bits"])


def read_stream(path, manifest):
    records, errors = [], []
    if not path.exists():
        return records, ["GPU evidence stream unavailable"]
    for line in path.read_bytes().splitlines(keepends=True):
        try:
            require(line.endswith(b"\n"), "truncated GPU evidence tail")
            r = read_json(line.decode())
            require(r["schema"] == SCHEMA, "unsupported GPU evidence schema")
            require(all(r[k] == manifest[k] for k in ("attempt_id", "series_id", "campaign_id")), "GPU identity mismatch")
            require(u64(r["sequence"]) == len(records), "GPU sequence gap or duplicate")
            require(r["clock_id"] == "linux.CLOCK_MONOTONIC", "unexpected GPU collection clock")
            now = u64(r["time_ns"])
            require(not records or now >= u64(records[-1]["time_ns"]), "nonmonotonic GPU record time")
            require(r["record_type"] in {"gpu_capability", "gpu_submission", "gpu_interval", "gpu_complete"}, "unknown GPU record type")
            records.append(r)
        except (ValueError, KeyError, TypeError, UnicodeError) as exc:
            errors.append(str(exc))
            break
    return records, errors


def summarize(records, errors, cpu_frames, config):
    """Keep absent submissions and unresolved tails visible; never infer zero."""
    errors = list(errors)
    capability, submissions, intervals = None, {}, {}
    complete = False
    for r in records:
        try:
            require(not complete, "GPU records after completion")
            kind = r["record_type"]
            now = u64(r["time_ns"])
            if kind == "gpu_capability":
                require(capability is None and not submissions, "duplicate or late GPU capability")
                period, bits = metadata(r)
                require(r["status"] in {"measured", "unsupported", "disabled", "collection_failure"} and r["reason"], "invalid GPU capability status")
                require((r["begin_stage"], r["end_stage"]) == ("TOP_OF_PIPE", "BOTTOM_OF_PIPE"), "GPU marker boundaries mismatch")
                u64(r["queue_family"])
                require(0 < u64(r["query_capacity"]) <= 3721, "invalid GPU query capacity")
                if r["status"] == "measured":
                    require(0 < bits <= 64 and math.isfinite(period) and period > 0, "invalid supported GPU capability")
                if r["status"] == "unsupported":
                    require(bits == 0, "unsupported status with supported timestamp bits")
                capability = r
            elif kind == "gpu_complete":
                require(capability is not None and u64(r["submissions"]) == len(submissions), "GPU completion submission count mismatch")
                complete = True
            else:
                require(capability is not None, "GPU capability unavailable")
                require(all(r[k] == capability[k] for k in ("scope", "period_bits", "period_ns", "valid_bits")), "GPU interval metadata mismatch")
                sid, frame, begin = u64(r["submission"]), u64(r["frame"]), u64(r["submit_begin_ns"])
                require(begin <= now, "GPU submission predates invalid CPU boundary")
                require(frame <= int(config["warmup"])+int(config["frames"]), "GPU origin outside frozen schedule")
                if kind == "gpu_submission":
                    require(sid == len(submissions) and frame == sid, "GPU submission/frame sequence mismatch")
                    require(sid < u64(capability["query_capacity"]), "GPU submission exceeds query capacity")
                    require(not submissions or begin >= u64(submissions[sid-1]["submit_begin_ns"]), "GPU submit clock regression")
                    submissions[sid] = r
                    continue
                require(sid in submissions and all(r[k] == submissions[sid][k] for k in ("frame", "submit_begin_ns")), "GPU interval origin mismatch")
                previous = intervals.get(sid)
                require(previous is None or previous["status"] == "not_ready", "duplicate terminal GPU interval")
                require(r["status"] in STATES and r["reason"] and r["unit"] == "ns", "invalid GPU measurement status")
                require((r["collection_phase"] == "teardown" and r["collection_frame"] is None) or
                        (r["collection_phase"] == "frame" and frame <= u64(r["collection_frame"]) <=
                         int(config["warmup"])+int(config["frames"])), "invalid GPU collection association")
                end = r["completion_ns"]
                if end is not None:
                    end = u64(end)
                    require(end <= now, "GPU completion bound after collection")
                if previous:
                    require(previous["completion_ns"] == r["completion_ns"], "GPU completion bound changed on delayed collection")
                raw, availability = r["raw_ticks"], r["availability"]
                if raw is not None:
                    require(len(raw) == len(availability) == 2, "invalid GPU query pair")
                    for tick, ready in zip(raw, availability):
                        require((u64(ready) != 0) == (tick is not None), "GPU tick availability mismatch")
                        if tick is not None:
                            u64(tick)
                else:
                    require(availability is None, "GPU availability without raw pair")
                status = r["status"]
                if status == "measured":
                    require(capability["status"] == "measured" and r["vk_result"] == "0", "measurement without successful supported query")
                    require(end is not None and begin <= end, "invalid CPU bounding interval")
                    require(raw is not None and all(u64(a) for a in availability), "measured GPU pair unavailable")
                    period, bits = metadata(r)
                    start, finish = map(u64, raw)
                    require(max(start, finish) < 2**bits, "GPU ticks outside valid bit range")
                    tick_ns = Fraction(period)
                    require(end-begin < 2**bits*tick_ns, "ambiguous GPU timestamp wrap")
                    delta = (finish-start) % 2**bits
                    duration = delta*tick_ns
                    require(duration <= end-begin+tick_ns and duration <= 2**64-1, "GPU interval outside CPU/range bound")
                    require(r["range_status"] == ("single_wrap" if finish < start else "valid"), "GPU range status mismatch")
                    require(u64(r["duration_ticks"]) == delta and type(r["value"]) in (int, float) and
                            math.isfinite(r["value"]) and r["value"] == float(duration), "GPU resolved interval mismatch")
                else:
                    require(r["value"] is None and r["duration_ticks"] is None, "unavailable GPU interval has a numeric value")
                    if status in {"unsupported", "disabled"}:
                        require(capability["status"] == status, "GPU capability/status contradiction")
                intervals[sid] = r
        except (ValueError, KeyError, TypeError, OverflowError) as exc:
            errors.append(str(exc))
            break
    # Include submitted work even if its CPU frame never returned, plus every
    # completed CPU frame even if its GPU submission/terminal record was lost.
    expected = {u64(f["frame"]) for f in cpu_frames} | {u64(s["frame"]) for s in submissions.values()}
    by_frame = {u64(r["frame"]): r for r in intervals.values()}
    resolved = []
    for frame in sorted(expected):
        r = by_frame.get(frame)
        if r is None or r["status"] == "not_ready":
            r = {"frame": str(frame), "submission": str(frame) if frame in submissions else None,
                 "status": "incomplete", "value": None, "unit": "ns", "scope": SCOPE,
                 "reason": "missing final GPU interval", "last_observation": r}
        resolved.append(r)
    if expected and (capability is None or not complete):
        errors.append("missing GPU capability or teardown completion")
    counts = {state: str(sum(r["status"] == state for r in resolved)) for state in sorted(STATES)}
    usable = bool(resolved) and not errors and all(r["status"] in {"measured", "unsupported"} for r in resolved)
    statuses = {r["status"] for r in resolved}
    state = next(iter(statuses)) if len(statuses) == 1 and not errors else "incomplete" if expected or errors else "not_executed"
    from megascene_static import distribution
    populations = {}
    for name in (("startup", "warmup", "ordinary", "edit", "motion") if config.get("case")=="support" else ("startup", "warmup", "ordinary", "edit")):
        def population(r):
            frame = int(r["frame"])
            if config.get("case") == "support":
                ordinal=frame-int(config['warmup'])-1
                if ordinal in (0,6,12,18,24,30): return "edit"
                if 31<=ordinal<=42: return "motion"
            if config.get("case") == "localized" and frame == int(config["warmup"])+1:
                return "edit"
            return "startup" if frame == 0 else "warmup" if frame <= int(config["warmup"]) else "ordinary"
        populations[name] = distribution([r["value"] for r in resolved if r["status"] == "measured" and population(r) == name])
    return {"status": state, "scope": SCOPE, "unit": "ns", "capability": capability,
            "required_evidence_complete": usable, "counts": counts, "intervals": resolved, "populations": populations,
            "errors": errors, "evidence": ["gpu.jsonl"],
            "reason": "GPU query availability only; no calibration, supervision, validation or performance qualification implied"}
