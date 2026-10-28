#!/usr/bin/env python3
"""Verify the historical voxel consumer separately from the Vulkan API suite."""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
LIBRARY = ROOT.parent / "deps/bend-vulkan"
BUILD = ROOT / "build"
BEND_VERSION = "2.0.39"


def run(*args, **kwargs):
    print("+", " ".join(map(str, args)), flush=True)
    try:
        return subprocess.run(args, cwd=ROOT, check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        for output, stream in ((error.stdout, sys.stdout), (error.stderr, sys.stderr)):
            if output:
                print(output.decode(errors="replace") if isinstance(output, bytes) else output,
                      end="", file=stream, flush=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitize", action="store_true", help="also run native checks under ASan and UBSan")
    parser.add_argument("--presentation", action="store_true", help="also require real X11 window acceptance and presentation failure probes")
    parser.add_argument("--isolated-display", action="store_true", help="use a private rootful Xwayland server for presentation checks")
    args = parser.parse_args()
    if args.isolated_display and not args.presentation:
        parser.error("--isolated-display requires --presentation")
    if not (LIBRARY / "deps/bend-collections/src/math/u64.bend").is_file():
        raise SystemExit("Initialize the pinned dependency: git submodule update --init --recursive deps/bend-vulkan (from the bend-voxel root)")
    if not (ROOT.parent / "voxel.bend").is_file():
        raise SystemExit("Expected voxel.bend in the owning bend-voxel repository")
    if not shutil.which("bend"):
        raise SystemExit(f"Bend {BEND_VERSION} is required on PATH")
    version = subprocess.run(["bend", "version"], cwd=ROOT, check=True,
                             text=True, capture_output=True).stdout.strip()
    if version != f"bend {BEND_VERSION}":
        raise SystemExit(f"The native effect ABI requires bend {BEND_VERSION}; found {version}")
    BUILD.mkdir(exist_ok=True)
    run(sys.executable, "tools/check_measurement.py")
    run(sys.executable, "tools/check_timing.py", *(["--sanitize"] if args.sanitize else []))
    run(sys.executable, "tools/build_shaders.py", "--check")
    run("bend", "PROOF.bend")
    run(sys.executable, "tools/check_geometry.py")
    run(sys.executable, "tools/check_chunks.py")
    run(sys.executable, "tools/check_generations.py", *(["--sanitize"] if args.sanitize else []))
    run(sys.executable, "tools/check_retirement.py", *(["--sanitize"] if args.sanitize else []))
    run(sys.executable, "tools/check_installation.py", *(["--sanitize"] if args.sanitize else []))
    run(sys.executable, "tools/check_uploads.py", *(["--sanitize"] if args.sanitize else []))
    run(sys.executable, "tools/check_appearance_math.py")
    run(sys.executable, "tools/check_reference_lighting.py")
    run(sys.executable, "tools/check_appearance_gpu.py", *(["--sanitize"] if args.sanitize else []))
    run(sys.executable, "tools/check_production.py", *(["--sanitize"] if args.sanitize else []))
    for source, name, expected in (
        ('tests/geometry_device.bend', 'geometry-device', 'Actual Vulkan Atelier logical-array bytes, state equality, resource rows and rendered rectangles passed'),
        ('examples/voxel_offscreen.bend', 'voxel-offscreen', 'Voxel complete geometry, RGBA8+D32 references'),
        ('tests/viewport.bend', 'viewport', 'Viewport square rays, wide-field picking and extent rejection passed'),
        ('tests/interactive.bend', 'interactive', 'Queued edit/reset picking before upload passed'),
    ):
        binary = BUILD / name
        run("bend", source, "-o", str(binary))
        result = run(str(binary), text=True, capture_output=True, timeout=180)
        (BUILD / f"{name}.log").write_text(result.stdout + result.stderr)
        print(result.stdout, end="", flush=True)
        if expected not in result.stdout:
            raise SystemExit(f"{name} omitted its success marker")
        if name in {"voxel-offscreen", "geometry-device"}:
            linked = subprocess.run(["ldd", str(binary)], check=True, text=True, capture_output=True).stdout
            if "libX11" in linked or "libxcb" in linked:
                raise SystemExit(f"Headless binary gained a display dependency: {name}")
    discovery = BUILD / "discover"
    run("bend", str(LIBRARY / "examples/discover.bend"), "-o", str(discovery))
    result = run(str(discovery), text=True, capture_output=True, timeout=60)
    if "Layer: VK_LAYER_KHRONOS_validation\n" in result.stdout:
        environment = dict(os.environ, VK_INSTANCE_LAYERS="VK_LAYER_KHRONOS_validation",
                           VK_LAYER_ENABLES="VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT")
        for name in ("geometry-device", "voxel-offscreen"):
            result = run(str(BUILD / name), env=environment, text=True, capture_output=True, timeout=180)
            diagnostics = result.stdout + result.stderr
            (BUILD / f"{name}-validation.log").write_text(diagnostics)
            if "Validation Error" in diagnostics or "SYNC-HAZARD" in diagnostics:
                raise SystemExit(f"Vulkan validation failed for {name}:\n{diagnostics}")
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", UBSAN_OPTIONS="halt_on_error=1")
    voxel_c = BUILD / "voxel-offscreen.c"
    run("bend", "examples/voxel_offscreen.bend", "-o", str(voxel_c))
    preprocessed = BUILD / "voxel-offscreen-preprocessed.c"
    run("clang", "-std=c11", "-E", "-P", str(voxel_c), "-o", str(preprocessed))
    if re.search(r"\b(?:cuLaunchKernel|cuInit|nvrtcCreateProgram)\s*\(", preprocessed.read_text()):
        raise SystemExit("CPU voxel translation unit retains CUDA dispatch")
    if (BUILD / "voxel-offscreen.gpu").exists():
        raise SystemExit("Unexpected voxel GPU artifact; remove the stale build artifact and rerun")
    if args.sanitize:
        voxel_sanitized = BUILD / "voxel-offscreen-sanitized"
        run("clang", "-std=c11", "-O1", "-g", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", str(voxel_c), "-lpthread", "-lm", "-ldl", "-o", str(voxel_sanitized))
        completed = run(str(voxel_sanitized), env=env, text=True, capture_output=True, timeout=240)
        (BUILD / "voxel-offscreen-sanitized.log").write_text(completed.stdout + completed.stderr)
        print(completed.stdout, end="", flush=True)
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
    geometry_c = BUILD / "geometry-device.c"
    run("bend", "tests/geometry_device.bend", "-o", str(geometry_c))
    geometry_preprocessed = BUILD / "geometry-device-preprocessed.c"
    run("clang", "-std=c11", "-E", "-P", str(geometry_c), "-o", str(geometry_preprocessed))
    if re.search(r"\b(?:cuLaunchKernel|cuInit|nvrtcCreateProgram)\s*\(", geometry_preprocessed.read_text()):
        raise SystemExit("CPU geometry device translation unit retains CUDA dispatch")
    if (BUILD / "geometry-device.gpu").exists():
        raise SystemExit("Unexpected geometry device GPU artifact")
    if args.sanitize:
        geometry_sanitized = BUILD / "geometry-device-sanitized"
        run("clang", "-std=c11", "-O1", "-g", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", str(geometry_c), "-lpthread", "-lm", "-ldl", "-o", str(geometry_sanitized))
        completed = run(str(geometry_sanitized), env=env, text=True, capture_output=True, timeout=240)
        (BUILD / "geometry-device-sanitized.log").write_text(completed.stdout + completed.stderr)
        print(completed.stdout, end="", flush=True)
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
    if args.presentation:
        presentation_flags = (["--sanitize"] if args.sanitize else []) + (["--isolated-display"] if args.isolated_display else [])
        run(sys.executable, "tools/check_acquisition.py", *presentation_flags)
        run(sys.executable, "tools/check_presentation.py", *presentation_flags)
        run(sys.executable, "tools/check_window.py", "--build", "--all", *presentation_flags)
        run(sys.executable, "tools/check_atelier_window.py", "--binary", str(BUILD / ("voxel-interactive-sanitized" if args.sanitize else "voxel-interactive-checked")), *(["--isolated-display"] if args.isolated_display else []))
        run(sys.executable, "tools/check_window.py", "--product", *(["--isolated-display"] if args.isolated_display else []))
    print("Voxel consumer proofs and integration passed.")


if __name__ == "__main__":
    main()
