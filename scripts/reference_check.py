from itertools import product
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VECTORS = {"-x": (-1, 0, 0), "+x": (1, 0, 0), "-y": (0, -1, 0), "+y": (0, 1, 0), "-z": (0, 0, -1), "+z": (0, 0, 1)}


def cube(side):
    return {p: 1 for p in product(range(side), repeat=3)}


def faces(occupied):
    result = set()
    for name, delta in VECTORS.items():
        shifted = {tuple(p[i] - delta[i] for i in range(3)) for p in occupied}
        result.update((p, name, occupied[p]) for p in occupied.keys() - shifted)
    return result


def parse(text):
    cases = {}
    current = None
    for line in text.splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == "BEGIN":
            current = {"cells": {}, "faces": set(), "face_lines": 0}
            cases[words[1]] = current
        elif words[0] == "COUNT":
            current["count"] = int(words[1])
        elif words[0] == "C":
            current["cells"][tuple(map(int, words[1].split(",")))] = int(words[2])
        elif words[0] == "F":
            current["faces"].add((tuple(map(int, words[1].split(","))), words[2], int(words[3])))
            current["face_lines"] += 1
    return cases


def main():
    command = [str(ROOT / "build" / "geometry-tests"), "--gpu", "off"]
    output = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True).stdout
    actual = parse(output)
    full4 = cube(4)
    interior = full4.copy()
    del interior[(1, 1, 1)]
    full8 = cube(8)
    cut = {p: m for p, m in full8.items() if sum((v - 6) ** 2 for v in p) > 9}
    single = {(1, 1, 1): 7}
    expected = {"empty": {}, "single": single, "adjacent": single | {(2, 1, 1): 7}, "full4": full4, "interior": interior, "repeat": interior, "bounds": single, "far-brush": full4, "edges": {(0, 1, 1): 1, (3, 1, 1): 1}, "full8": full8, "cut": cut, "cut-repeat": cut}
    assert set(actual) == set(expected), (set(actual), set(expected))
    for name, occupied in expected.items():
        case = actual[name]
        expected_faces = faces(occupied)
        assert case["cells"] == occupied, f"{name}: occupancy differs"
        assert case["faces"] == expected_faces, f"{name}: exact exposed face set differs"
        assert case["count"] == case["face_lines"] == len(expected_faces), f"{name}: duplicate or missing faces"
        print(f"{name}: {len(occupied)} cells, {len(expected_faces)} exact faces")
    assert actual["full4"]["count"] == 96
    assert actual["interior"]["count"] == 102
    assert actual["full8"]["count"] == 384
    assert actual["cut"]["cells"].keys() < actual["full8"]["cells"].keys()
    assert actual["cut"] == actual["cut-repeat"]
    print("Geometry reference checks passed.")


if __name__ == "__main__":
    main()
