#!/usr/bin/env python3
"""Compare two prebuilt lookup-bench binaries, alternating process order."""
import argparse
import csv
import hashlib
import json
import pathlib
import platform
import statistics
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=pathlib.Path)
    parser.add_argument('after', type=pathlib.Path)
    parser.add_argument('--rounds', type=int, default=20)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.rounds < 2 or args.rounds % 2:
        parser.error('--rounds must be positive, even, and at least two')
    binaries = {name: path.resolve() for name, path in
                [('before', args.before), ('after', args.after)]}
    expected = {'empty': 0, 'single': 115200, 'head': 115200,
                'middle': 729600, 'tail': 1344000, 'missing': 0}

    def run(name):
        proc = subprocess.run([str(binaries[name]), '--gpu', 'off', '--threads', '1'],
                              capture_output=True, text=True, check=True, timeout=60)
        rows = list(csv.reader(proc.stdout.splitlines()))
        assert len(rows) == len(expected), proc.stdout
        assert {label: float(checksum) for label, _, checksum in rows} == expected, proc.stdout
        return {label: int(duration) for label, duration, _ in rows}

    for name in binaries:
        run(name)  # One excluded warm-up process per binary.
    samples = []
    for index in range(args.rounds):
        order = ['before', 'after'] if index % 2 == 0 else ['after', 'before']
        for name in order:
            samples.append(dict(round=index + 1, variant=name, microseconds=run(name)))
    summary = {}
    for case in expected:
        medians = {name: statistics.median(s['microseconds'][case] for s in samples
                                          if s['variant'] == name) for name in binaries}
        summary[case] = {**medians, 'change_percent':
                         (medians['after'] / medians['before'] - 1) * 100}
    report = dict(bend=subprocess.check_output(['bend', 'version'], text=True).strip(),
                  platform=platform.platform(), backend='CPU', threads=1,
                  lookups_per_case=19200, warmup_processes_per_binary=1,
                  binary_sha256={name: hashlib.sha256(path.read_bytes()).hexdigest()
                                 for name, path in binaries.items()},
                  checksums=expected, samples=samples, median_microseconds=summary)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
