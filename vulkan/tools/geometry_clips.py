#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def cells(rect):
    a, b, c, d = rect
    assert a < b and c < d, f'nonpositive rectangle {rect}'
    return {(u, v) for u in range(a, b) for v in range(c, d)}


def check(path):
    count = 0
    keys = set()
    for line in Path(path).read_text().splitlines():
        if not line.startswith('['):
            continue
        source, blocker, actual = json.loads(line)
        key = tuple(source + blocker)
        assert key not in keys
        keys.add(key)
        remaining = cells(source) - cells(blocker)
        seen = set()
        assert len(actual) <= 4, 'more than four fragments'
        for rectangle in actual:
            covered = cells(rectangle)
            assert not covered & seen, 'duplicate subtraction coverage'
            seen |= covered
        assert seen == remaining, f'wrong difference {source} {blocker}'
        count += 1
    assert count == 10000, f'incomplete 0..4 valid rectangle cross-product {count}'
    print(f'PASS exhaustive {count} rectangle differences, positive fragments, exact coverage and disjointness')


if __name__ == '__main__':
    check(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'build/geometry-clips.jsonl')
