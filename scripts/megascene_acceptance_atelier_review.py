#!/usr/bin/env python3
"""Capture the unchanged Light Atelier controls on the real X11 Vulkan window."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from PIL import Image, ImageChops
from Xlib import X, XK, display
from Xlib.ext import xtest


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def wait_window(screen, old, process):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"application exited before window creation: {process.returncode}")
        for window in screen.root.query_tree().children:
            if window.id in old:
                continue
            try:
                if "Bend Voxel Vulkan" in (window.get_wm_name() or ""):
                    return window
            except Exception:
                pass
        time.sleep(0.1)
    raise RuntimeError("Light Atelier window not found")


def capture(window, output):
    subprocess.run(["import", "-window", f"0x{window.id:x}", str(output)],
                   check=True, timeout=15)
    return {"path": str(output), "sha256": sha(output)}


def difference(a, b, width, height):
    with Image.open(a) as left, Image.open(b) as right:
        if left.size != (width, height) or right.size != (width, height):
            raise RuntimeError(f"unexpected window capture size: {left.size}, {right.size}")
        box = (0, height // 6, width, height * 5 // 6)
        delta = ImageChops.difference(left.convert("RGB").crop(box),
                                      right.convert("RGB").crop(box))
        pixels = delta.tobytes()
        return sum(any(pixels[i:i + 3]) for i in range(0, len(pixels), 3))


def key(x11, symbol, pressed):
    code = x11.keysym_to_keycode(XK.string_to_keysym(symbol))
    xtest.fake_input(x11, X.KeyPress if pressed else X.KeyRelease, code)
    x11.sync()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resolution", choices=("640x360", "1920x1080"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--binary", type=Path, default=Path("build/voxel-demo"))
    args = parser.parse_args()
    width, height = map(int, args.resolution.split("x"))
    args.output.mkdir(parents=True, exist_ok=False)
    x11 = display.Display()
    old = {window.id for window in x11.screen().root.query_tree().children}
    env = dict(os.environ, VOXEL_RESOLUTION=args.resolution)
    with (args.output / "stdout.log").open("w") as stdout, \
         (args.output / "stderr.log").open("w") as stderr:
        process = subprocess.Popen([str(args.binary), "--gpu", "off"],
                                   stdout=stdout, stderr=stderr, env=env,
                                   start_new_session=True)
        try:
            window = wait_window(x11.screen(), old, process)
            window.set_input_focus(X.RevertToPointerRoot, X.CurrentTime)
            # Xwayland delivers keyboard input only after the client has also
            # received a pointer focus event. A short RMB press changes no world.
            window.warp_pointer(10, height - 10)
            xtest.fake_input(x11, X.ButtonPress, 3)
            xtest.fake_input(x11, X.ButtonRelease, 3)
            x11.sync()
            time.sleep(1)
            captures = {}
            captures["day"] = capture(window, args.output / "day.png")
            key(x11, "l", True)
            time.sleep(0.4)
            captures["night"] = capture(window, args.output / "night.png")
            key(x11, "l", False)
            time.sleep(0.4)
            window.warp_pointer(int(width * 0.56), int(height * 0.43))
            x11.sync()
            time.sleep(0.4)
            captures["target"] = capture(window, args.output / "target.png")
            xtest.fake_input(x11, X.ButtonPress, 1)
            x11.sync()
            time.sleep(0.1)
            xtest.fake_input(x11, X.ButtonRelease, 1)
            x11.sync()
            time.sleep(0.5)
            captures["cut"] = capture(window, args.output / "cut.png")
            for label, symbol in (("forward", "w"), ("backward", "s"),
                                  ("left", "a"), ("right", "d"),
                                  ("down", "q"), ("up", "e")):
                key(x11, symbol, True)
                time.sleep(0.22)
                key(x11, symbol, False)
                time.sleep(0.1)
                captures[label] = capture(window, args.output / f"{label}.png")
            key(x11, "Shift_L", True)
            key(x11, "w", True)
            time.sleep(0.22)
            key(x11, "w", False)
            key(x11, "Shift_L", False)
            time.sleep(0.1)
            captures["fast"] = capture(window, args.output / "fast.png")
            window.warp_pointer(width // 2, height // 2)
            xtest.fake_input(x11, X.ButtonPress, 3)
            x11.sync()
            window.warp_pointer(width // 2 + width // 10, height // 2)
            x11.sync()
            time.sleep(0.2)
            xtest.fake_input(x11, X.ButtonRelease, 3)
            x11.sync()
            time.sleep(0.2)
            captures["look"] = capture(window, args.output / "look.png")
            key(x11, "r", True)
            time.sleep(0.1)
            key(x11, "r", False)
            time.sleep(0.6)
            captures["reset"] = capture(window, args.output / "reset.png")
            result = {"schema": "light-atelier-interactive-review/1",
                      "resolution": args.resolution, "window_id": f"0x{window.id:x}",
                      "binary": str(args.binary), "binary_sha256": sha(args.binary),
                      "captures": captures,
                      "scene_changed_pixels": {
                          "night_vs_day": difference(args.output / "day.png",
                                                     args.output / "night.png", width, height),
                          "cut_vs_target": difference(args.output / "target.png",
                                                      args.output / "cut.png", width, height),
                          "forward_vs_cut": difference(args.output / "cut.png",
                                                       args.output / "forward.png", width, height),
                          "look_vs_fast": difference(args.output / "fast.png",
                                                     args.output / "look.png", width, height),
                          "reset_vs_day": difference(args.output / "day.png",
                                                     args.output / "reset.png", width, height)},
                      "visual_review": "pending"}
            (args.output / "review.json").write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result["scene_changed_pixels"]))
        finally:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


if __name__ == "__main__":
    main()
