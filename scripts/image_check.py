import argparse
import hashlib
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build" / "bend-voxel-rewrite"


def read_ppm(path):
    values = path.read_text().split()
    assert values[:4] == ["P3", "512", "512", "255"], path
    pixels = bytes(map(int, values[4:]))
    assert len(pixels) == 512 * 512 * 3
    return pixels


def pixel(pixels, x, y):
    start = 3 * (512 * y + x)
    return tuple(pixels[start:start + 3])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cpu-only", action="store_true")
    args = parser.parse_args()
    out = ROOT / "build" / "image-check"
    out.mkdir(parents=True, exist_ok=True)
    baseline = {}
    lanes = ["off"] if args.cpu_only else ["off", "on"]
    for cut in [False, True]:
        for gpu in lanes:
            for tile, fork in [(4, 0), (4, 4), (5, 5), (6, 6)]:
                path = out / f"{'cut' if cut else 'full'}-{gpu}-{tile}-{fork}.ppm"
                command = [str(BINARY), "--gpu", gpu, "--threads", "1", "--tile-depth", str(tile), "--fork-depth", str(fork), "--dump", str(path)]
                if cut:
                    command.append("--cut")
                subprocess.run(command, cwd=ROOT, check=True)
                pixels = read_ppm(path)
                if cut not in baseline:
                    baseline[cut] = pixels
                assert pixels == baseline[cut], f"Image differs for cut={cut}, GPU={gpu}, tile={tile}, fork={fork}"
                print(f"cut={cut} GPU={gpu} tile={tile} fork={fork}: exact image equal")
    assert pixel(baseline[False], 0, 0) == (16, 24, 32)
    assert pixel(baseline[False], 256, 256) == (229, 188, 122)
    assert pixel(baseline[False], 256, 300) == (160, 114, 72)
    assert baseline[False] != baseline[True]
    changed = sum(a != b for a, b in zip(zip(*[iter(baseline[False])] * 3), zip(*[iter(baseline[True])] * 3)))
    assert changed == 18520, changed
    for cut, pixels in baseline.items():
        print(f"{'cut' if cut else 'full'} RGB sha256={hashlib.sha256(pixels).hexdigest()}")
    print(f"Image checks passed. Destruction changed {changed} pixels.")


if __name__ == "__main__":
    main()
