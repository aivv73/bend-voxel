import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build" / "bend-voxel-rewrite"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=int, default=24)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--output", type=Path, default=ROOT / "build" / "benchmark.json")
    cores = os.cpu_count() or 1
    parser.add_argument("--cpu-threads", type=int, nargs="+", default=sorted({1, max(1, cores // 2), cores}))
    args = parser.parse_args()
    assert args.frames >= 24 and args.repeats >= 2
    assert all(n > 0 for n in args.cpu_threads)
    configs = [("off", 1, 6, 0)] + [("off", n, 6, 6) for n in args.cpu_threads] + [("on", 1, 4, 0), ("on", 1, 4, 4), ("on", 1, 5, 5), ("on", 1, 6, 6)]
    samples = {config: [] for config in configs}
    for repeat in range(args.repeats):
        for gpu, threads, tile, fork in configs[::1 if repeat % 2 == 0 else -1]:
            command = [str(BINARY), "--gpu", gpu, "--threads", str(threads), "--tile-depth", str(tile), "--fork-depth", str(fork), "--bench", str(args.frames)]
            output = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True).stdout
            match = re.search(r"frames=(\d+) elapsed_ms=(\d+)", output)
            assert match and int(match[1]) == args.frames, output
            value = int(match[2]) / args.frames
            samples[(gpu, threads, tile, fork)].append(value)
            print(f"repeat={repeat + 1} gpu={gpu} threads={threads} tile={tile} fork={fork} ms/frame={value:.3f}", flush=True)
    rows = [{"gpu": gpu, "threads": threads, "tile_depth": tile, "fork_depth": fork, "samples_ms_per_frame": values, "median_ms_per_frame": statistics.median(values)} for (gpu, threads, tile, fork), values in samples.items()]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "binary_sha256": hashlib.sha256(BINARY.read_bytes()).hexdigest(),
        "source_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in ("main.bend", "voxel.bend", "render.bend", "dump.bend")},
        "frames": args.frames,
        "warmup_frames": 8,
        "repeats": args.repeats,
        "workload": "native Window.frame with cached scene and scripted destruction/reset",
        "results": rows,
    }
    args.output.write_text(json.dumps(record, indent=2) + "\n")
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
