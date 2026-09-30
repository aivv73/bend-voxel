#!/usr/bin/env python3
"""Drive an owned Light Atelier X11 window and retain verification evidence."""
import argparse
import ctypes as C
import ctypes.util
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[4]
TITLE = "Bend Voxel Vulkan - WASD / RMB look / LMB carve / R reset"
ARTIFACTS = ["voxel-demo", "libvoxel_vulkan.so", "vulkan-scene.vert.spv",
             "vulkan-scene.frag.spv", "vulkan-shadow.vert.spv"]
FEATURES = ["opening", "lighting", "carve-reset", "navigation"]


class PointerEvent(C.Structure):
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int),
                ("display", C.c_void_p), ("window", C.c_ulong), ("root", C.c_ulong),
                ("subwindow", C.c_ulong), ("time", C.c_ulong), ("x", C.c_int),
                ("y", C.c_int), ("x_root", C.c_int), ("y_root", C.c_int),
                ("state", C.c_uint), ("detail", C.c_uint), ("same_screen", C.c_int)]


class ClientData(C.Union):
    _fields_ = [("b", C.c_char * 20), ("s", C.c_short * 10), ("l", C.c_long * 5)]


class ClientEvent(C.Structure):
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int),
                ("display", C.c_void_p), ("window", C.c_ulong),
                ("message_type", C.c_ulong), ("format", C.c_int), ("data", ClientData)]


class Event(C.Union):
    _fields_ = [("pointer", PointerEvent), ("client", ClientEvent), ("pad", C.c_long * 24)]


class X11:
    def __init__(self):
        library = ctypes.util.find_library("X11")
        if not library:
            raise RuntimeError("libX11 is unavailable")
        self.lib = C.CDLL(library)
        signatures = {
            "XOpenDisplay": ([C.c_char_p], C.c_void_p),
            "XCloseDisplay": ([C.c_void_p], C.c_int),
            "XDefaultRootWindow": ([C.c_void_p], C.c_ulong),
            "XQueryTree": ([C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong),
                            C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ulong)),
                            C.POINTER(C.c_uint)], C.c_int),
            "XFetchName": ([C.c_void_p, C.c_ulong, C.POINTER(C.c_void_p)], C.c_int),
            "XFree": ([C.c_void_p], C.c_int),
            "XStringToKeysym": ([C.c_char_p], C.c_ulong),
            "XKeysymToKeycode": ([C.c_void_p, C.c_ulong], C.c_ubyte),
            "XSendEvent": ([C.c_void_p, C.c_ulong, C.c_int, C.c_long,
                            C.POINTER(Event)], C.c_int),
            "XFlush": ([C.c_void_p], C.c_int),
            "XInternAtom": ([C.c_void_p, C.c_char_p, C.c_int], C.c_ulong),
            "XSetErrorHandler": ([C.c_void_p], C.c_void_p),
        }
        for name, (arguments, result) in signatures.items():
            function = getattr(self.lib, name)
            function.argtypes, function.restype = arguments, result
        self.error_handler = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p)(lambda display, error: 0)
        self.previous_handler = self.lib.XSetErrorHandler(C.cast(self.error_handler, C.c_void_p))
        self.display = self.lib.XOpenDisplay(None)
        if not self.display:
            self.lib.XSetErrorHandler(self.previous_handler)
            raise RuntimeError(f"Cannot open DISPLAY={os.environ.get('DISPLAY')!r}")
        self.root = self.lib.XDefaultRootWindow(self.display)

    def close(self):
        self.lib.XCloseDisplay(self.display)
        self.lib.XSetErrorHandler(self.previous_handler)

    def title(self, window):
        name = C.c_void_p()
        if not self.lib.XFetchName(self.display, window, C.byref(name)) or not name.value:
            return ""
        try:
            return C.string_at(name).decode(errors="replace")
        finally:
            self.lib.XFree(name)

    def windows(self):
        found = set()
        pending = [self.root]
        while pending:
            window = pending.pop()
            if self.title(window) == TITLE:
                found.add(window)
            root, parent, children, count = C.c_ulong(), C.c_ulong(), C.POINTER(C.c_ulong)(), C.c_uint()
            if self.lib.XQueryTree(self.display, window, C.byref(root), C.byref(parent),
                                  C.byref(children), C.byref(count)):
                pending.extend(children[index] for index in range(count.value))
            if children:
                self.lib.XFree(children)
        return found

    def send(self, window, kind, x=12, y=100, detail=0, state=0):
        event = Event()
        p = event.pointer
        p.type, p.send_event, p.display = kind, 1, self.display
        p.window, p.root, p.x, p.y, p.same_screen = window, self.root, x, y, 1
        p.detail, p.state = detail, state
        masks = {2: 1, 3: 2, 4: 4, 5: 8, 6: 64}
        if not self.lib.XSendEvent(self.display, window, 0, masks[kind], C.byref(event)):
            raise RuntimeError("XSendEvent failed")
        self.lib.XFlush(self.display)

    def key(self, window, name, down):
        symbol = self.lib.XStringToKeysym(name.encode())
        code = self.lib.XKeysymToKeycode(self.display, symbol)
        if not code:
            raise RuntimeError(f"No X11 keycode for {name}")
        self.send(window, 2 if down else 3, detail=code)

    def quit(self, window):
        event = Event()
        event.client.type, event.client.display, event.client.window = 33, self.display, window
        event.client.message_type = self.lib.XInternAtom(self.display, b"WM_PROTOCOLS", 0)
        event.client.format = 32
        event.client.data.l[0] = self.lib.XInternAtom(self.display, b"WM_DELETE_WINDOW", 0)
        self.lib.XSendEvent(self.display, window, 0, 0, C.byref(event))
        self.lib.XFlush(self.display)


def doctor():
    version = subprocess.check_output(["bend", "version"], text=True).strip()
    if version != "bend 2.0.34":
        raise RuntimeError(f"Expected bend 2.0.34, found {version}")
    sources = [path for path in (ROOT / "src").rglob("*") if path.is_file()]
    sources.extend([ROOT / "scripts/build.sh", ROOT / "Makefile"])
    newest = max(path.stat().st_mtime_ns for path in sources)
    hashes = {}
    for name in ARTIFACTS:
        path = ROOT / "build" / name
        if not path.is_file() or path.stat().st_mtime_ns < newest:
            raise RuntimeError(f"Missing or stale {path}; run make build")
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    subprocess.run(["import", "-version"], check=True, capture_output=True, timeout=10)
    x = X11()
    x.close()
    return {"bend": version, "display": os.environ.get("DISPLAY"), "build_sha256": hashes}


def megascene_doctor(archive):
    """Read prerequisites and the existing allowance without creating a lease."""
    version = subprocess.check_output(["bend", "version"], text=True).strip()
    if version != "bend 2.0.34":
        raise RuntimeError(f"Expected bend 2.0.34, found {version}")
    commands = {name: shutil.which(name) for name in ("clang", "g++", "glslc", "python3")}
    libraries = {name: ctypes.util.find_library(name)
                 for name in ("X11", "vulkan", "crypto", "atomic", "nvidia-ml")}
    missing = [name for name, path in {**commands, **libraries}.items() if not path]
    if missing:
        raise RuntimeError(f"Missing Megascene prerequisites: {', '.join(missing)}")
    x = X11()
    x.close()
    archive = archive.expanduser().resolve()
    if any(part in ("build", "dist", "tmp") for part in archive.parts):
        raise RuntimeError("Megascene archive must be outside disposable build/dist/tmp directories")
    ledger_path = archive / "campaign.json"
    campaign = {"path": str(ledger_path), "state": "not_started"}
    if ledger_path.exists():
        ledger = json.loads(ledger_path.read_text())
        if ledger["schema"] != "megascene-evidence/1":
            raise RuntimeError("Unsupported Megascene campaign schema")
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        elapsed_since_lease = (time.monotonic_ns() - int(ledger["lease_ns"])
                              if boot == ledger["boot_id"]
                              else time.time_ns() - int(ledger["lease_utc_ns"]))
        remaining = max(0, int(ledger["allowance_ns"]) - int(ledger["elapsed_ns"])
                        - max(0, elapsed_since_lease))
        campaign.update(state=ledger["state"], campaign_id=ledger["campaign_id"],
                        remaining_seconds=remaining / 1e9)
        if ledger["state"] != "ready" or remaining == 0:
            raise RuntimeError(f"Campaign unavailable: {json.dumps(campaign)}; follow docs/megascene-supervision.md")
    return {"surface": "megascene", "bend": version, "display": os.environ.get("DISPLAY"),
            "commands": commands, "libraries": libraries, "archive": str(archive),
            "campaign": campaign,
            "monitoring": "Vulkan capability, device attribution and reserves require the runner's supervised preflight"}


def scene(image):
    return image.convert("RGB").crop((0, 90, 640, 300))


def changed(a, b):
    data = ImageChops.difference(scene(a), scene(b)).tobytes()
    return sum(data[index:index + 3] != b"\x00\x00\x00" for index in range(0, len(data), 3))


class Drive:
    def __init__(self, directory, x):
        self.directory, self.x = directory, x
        self.process = None
        self.window = None
        self.actions = []

    def record(self, action, **fields):
        entry = {"time_ns": time.monotonic_ns(), "action": action, **fields}
        self.actions.append(entry)
        with (self.directory / "actions.jsonl").open("a") as stream:
            stream.write(json.dumps(entry) + "\n")

    def launch(self):
        before = self.x.windows()
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(("VOXEL_", "MEGASCENE_"))}
        environment.update(VOXEL_RESOLUTION="640x360", VOXEL_VULKAN_TRACE="1",
                           VOXEL_VERIFY_BEND_MESH="1")
        command = [str(ROOT / "build/voxel-demo"), "--gpu", "off", "--threads", "1"]
        with (self.directory / "stdout.log").open("w") as output, (self.directory / "stderr.log").open("w") as errors:
            self.process = subprocess.Popen(command, cwd=ROOT, env=environment,
                                            stdout=output, stderr=errors, start_new_session=True)
        self.record("launch", command=command, pid=self.process.pid,
                    environment={key: value for key, value in environment.items() if key.startswith("VOXEL_")})
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError(f"Application exited {self.process.returncode}; see stderr.log")
            candidates = self.x.windows() - before
            if len(candidates) > 1:
                raise RuntimeError("Ambiguous new Light Atelier windows; refusing to drive")
            if candidates:
                self.window = candidates.pop()
            trace = (self.directory / "stderr.log").read_text()
            if self.window and "vulkan shadow refresh bodies" in trace:
                self.record("doctor", window=hex(self.window), title=self.x.title(self.window),
                            ownership="sole new exact-title window after owned process launch")
                self.click(610, 12)
                self.move(12, 100)
                return
            time.sleep(0.1)
        raise RuntimeError("No rendered owned window within 30 seconds")

    def healthy(self):
        if self.process.poll() is not None or self.x.title(self.window) != TITLE:
            raise RuntimeError("Owned instance is no longer healthy")

    def settle(self):
        time.sleep(0.35)
        self.healthy()

    def move(self, x, y, state=0):
        self.healthy()
        self.record("pointer", x=x, y=y, state=state)
        self.x.send(self.window, 6, x, y, state=state)
        self.settle()

    def button(self, x, y, number, down):
        self.healthy()
        self.record("button", x=x, y=y, number=number, down=down)
        self.x.send(self.window, 4 if down else 5, x, y, detail=number)
        self.settle()

    def click(self, x, y):
        self.button(x, y, 1, True)
        self.button(x, y, 1, False)

    def key(self, name, down):
        self.healthy()
        self.record("key", name=name, down=down)
        self.x.key(self.window, name, down)
        self.settle()

    def reset(self):
        self.key("r", True)
        self.key("r", False)
        self.move(12, 100)

    def capture(self, label):
        self.healthy()
        path = self.directory / f"{label}.png"
        subprocess.run(["import", "-window", hex(self.window), str(path)],
                       check=True, capture_output=True, timeout=10)
        with Image.open(path) as source:
            image = source.convert("RGB")
        if image.size != (640, 360):
            raise RuntimeError(f"Unexpected client capture dimensions: {image.size}")
        self.record("capture", path=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        return image

    def cleanup(self):
        if self.process is None:
            return
        if self.process.poll() is None:
            if self.window:
                self.record("close", window=hex(self.window))
                self.x.quit(self.window)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.record("terminate-owned-process-group", pid=self.process.pid)
                os.killpg(self.process.pid, signal.SIGTERM)
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait(timeout=5)
        self.record("cleanup", exit_code=self.process.returncode, process_stopped=True)


def exercise(drive, feature):
    baseline = drive.capture("before")
    pixels = scene(baseline).tobytes()
    if len({pixels[index:index + 3] for index in range(0, len(pixels), 3)}) < 100:
        raise RuntimeError("Opening scene is blank or has too little image detail")
    checks = {"opening_has_image_detail": True}
    if feature == "lighting":
        drive.key("l", True)
        night = drive.capture("night")
        drive.key("l", False)
        day = drive.capture("day-restored")
        checks.update(night_changed_pixels=changed(baseline, night),
                      restored_changed_pixels=changed(baseline, day))
        if checks["night_changed_pixels"] < 1000 or checks["restored_changed_pixels"]:
            raise RuntimeError(f"Lighting comparison failed: {checks}")
    elif feature == "carve-reset":
        drive.move(360, 186)
        drive.capture("aim-before-cut")
        drive.click(360, 186)
        drive.move(12, 100)
        cut = drive.capture("after-cut")
        drive.reset()
        reset = drive.capture("keyboard-reset")
        drive.move(360, 186)
        drive.click(360, 186)
        drive.move(12, 100)
        drive.capture("second-cut")
        drive.click(610, 12)
        drive.move(12, 100)
        button_reset = drive.capture("button-reset")
        checks.update(cut_changed_pixels=changed(baseline, cut),
                      keyboard_reset_changed_pixels=changed(baseline, reset),
                      button_reset_changed_pixels=changed(baseline, button_reset))
        if not checks["cut_changed_pixels"] or checks["keyboard_reset_changed_pixels"] or checks["button_reset_changed_pixels"]:
            raise RuntimeError(f"Carve/reset comparison failed: {checks}")
    elif feature == "navigation":
        drive.key("w", True)
        drive.key("w", False)
        moved = drive.capture("moved-forward")
        drive.reset()
        drive.move(320, 180)
        drive.button(320, 180, 3, True)
        drive.move(340, 180, state=1 << 10)
        drive.button(340, 180, 3, False)
        looked = drive.capture("looked-right")
        drive.reset()
        restored = drive.capture("navigation-reset")
        drive.move(360, 186)
        drive.capture("aim-sculpture")
        drive.key("Escape", True)
        drive.key("Escape", False)
        drive.capture("controls-released")
        drive.click(610, 12)
        drive.move(360, 186)
        drive.capture("controls-resumed")
        checks.update(movement_changed_pixels=changed(baseline, moved),
                      look_changed_pixels=changed(baseline, looked),
                      reset_changed_pixels=changed(baseline, restored))
        if not checks["movement_changed_pixels"] or not checks["look_changed_pixels"] or checks["reset_changed_pixels"]:
            raise RuntimeError(f"Navigation comparison failed: {checks}")
    return checks


def run(args):
    path = args.evidence.resolve()
    path.mkdir(parents=True, exist_ok=False)
    report = {"feature": args.feature, "evidence": str(path), "mechanical_pass": False,
              "visual_review": "pending", "error": None}
    x = None
    drive = None
    display_hash = hashlib.sha256(os.environ.get("DISPLAY", "").encode()).hexdigest()[:16]
    lock_path = Path(tempfile.gettempdir()) / f"bend-voxel-verification-{os.getuid()}-{display_hash}.lock"
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            report["doctor"] = doctor()
            report["git_revision"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
            report["working_tree_status"] = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).splitlines()
            report["harness_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
            x = X11()
            drive = Drive(path, x)
            drive.launch()
            report["checks"] = exercise(drive, args.feature)
            report["mechanical_pass"] = True
        except Exception as error:
            report["error"] = str(error)
        finally:
            if drive:
                try:
                    drive.cleanup()
                    report["exit_code"] = drive.process.returncode if drive.process else None
                    if report["exit_code"] != 0:
                        report["mechanical_pass"] = False
                except Exception as error:
                    report["cleanup_error"] = str(error)
                    report["mechanical_pass"] = False
            if x:
                x.close()
            (path / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["mechanical_pass"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    health = commands.add_parser("doctor", help="Read-only prerequisites for the selected surface")
    health.add_argument("--surface", choices=("light-atelier", "megascene"), default="light-atelier")
    health.add_argument("--archive", type=Path, help="Existing durable Megascene campaign root")
    verify = commands.add_parser("run", help="Launch, doctor, drive, capture, and clean up one owned instance")
    verify.add_argument("--feature", choices=FEATURES, required=True)
    verify.add_argument("--evidence", type=Path, required=True, help="New directory retained after cleanup")
    args = parser.parse_args()
    if args.command == "doctor":
        if args.surface == "megascene" and args.archive is None:
            parser.error("Megascene doctor requires --archive")
        if args.surface == "light-atelier" and args.archive is not None:
            parser.error("--archive applies to Megascene doctor")
        print(json.dumps(megascene_doctor(args.archive) if args.surface == "megascene" else doctor(), indent=2))
        return 0
    def interrupted(number, frame):
        raise RuntimeError(f"Verification interrupted by signal {number}")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
