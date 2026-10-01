import argparse
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageChops
from Xlib import X, XK, display, protocol


def find_window(connection, prefix):
    pending = [connection.screen().root]
    while pending:
        window = pending.pop()
        try:
            title = window.get_wm_name()
            if title and title.startswith(prefix):
                return window
            pending.extend(window.query_tree().children)
        except Exception:
            continue
    return None


def send_key(connection, window, name):
    fields = dict(
        time=X.CurrentTime,
        root=connection.screen().root,
        window=window,
        child=X.NONE,
        root_x=0,
        root_y=0,
        event_x=128,
        event_y=128,
        state=0,
        same_screen=1,
        detail=connection.keysym_to_keycode(XK.string_to_keysym(name)),
    )
    window.send_event(protocol.event.KeyPress(**fields), event_mask=X.KeyPressMask)
    window.send_event(protocol.event.KeyRelease(**fields), event_mask=X.KeyReleaseMask)
    connection.sync()


def capture(window, path):
    subprocess.run(
        ["import", "-window", str(window.id), str(path)],
        check=True,
        timeout=10,
    )
    with Image.open(path) as image:
        return image.convert("RGB")


def send_mouse(connection, window, x, y):
    fields = dict(
        time=X.CurrentTime,
        root=connection.screen().root,
        window=window,
        child=X.NONE,
        root_x=0,
        root_y=0,
        event_x=x,
        event_y=y,
        state=0,
        same_screen=1,
        detail=1,
    )
    window.send_event(protocol.event.ButtonPress(**fields), event_mask=X.ButtonPressMask)
    window.send_event(protocol.event.ButtonRelease(**fields), event_mask=X.ButtonReleaseMask)
    connection.sync()


def send_close(connection, window):
    message = protocol.event.ClientMessage(
        window=window,
        client_type=connection.intern_atom("WM_PROTOCOLS"),
        data=(32, [connection.intern_atom("WM_DELETE_WINDOW"), X.CurrentTime, 0, 0, 0]),
    )
    window.send_event(message, event_mask=X.NoEventMask)
    connection.sync()


def await_image(window, path, predicate, seconds=30):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        image = capture(window, path)
        if predicate(image):
            return image
        time.sleep(0.2)
    raise AssertionError(f"Window image did not meet its predicate: {path}")


def check_window(args, connection, process):
    deadline = time.monotonic() + 60
    window = None
    while window is None and time.monotonic() < deadline:
        if process:
            assert process.poll() is None, "Native app exited before opening its window"
        window = find_window(connection, args.title)
        time.sleep(0.2)
    assert window is not None, "Native Bend window was not found"
    before = await_image(
        window, args.output / "before.png", lambda image: len(image.getcolors(image.width * image.height) or []) > 4
    )
    send_key(connection, window, args.destroy_key)
    after = await_image(
        window,
        args.output / "destroyed.png",
        lambda image: image.size == before.size and ImageChops.difference(before, image).getbbox() is not None,
    )
    delta = ImageChops.difference(before, after).tobytes()
    differences = sum(delta[i:i + 3] != bytes(3) for i in range(0, len(delta), 3))
    assert differences > 100, f"Destruction changed only {differences} pixels"
    send_key(connection, window, args.reset_key)
    restored = await_image(
        window,
        args.output / "reset.png",
        lambda image: image.size == before.size and ImageChops.difference(before, image).getbbox() is None,
    )
    assert restored.tobytes() == before.tobytes(), "Reset did not restore the exact image"
    send_mouse(connection, window, 20, 20)
    time.sleep(0.35)
    background = capture(window, args.output / "background-click.png")
    assert background.tobytes() == before.tobytes(), "Background click changed the body image"
    send_mouse(connection, window, 256, 200)
    clicked = await_image(
        window,
        args.output / "clicked.png",
        lambda image: image.size == before.size and ImageChops.difference(before, image).getbbox() is not None,
    )
    assert clicked.tobytes() != before.tobytes(), "Primary click did not carve the picked face"
    assert clicked.tobytes() != after.tobytes(), "Primary click ignored its picked position"
    send_key(connection, window, args.reset_key)
    await_image(
        window,
        args.output / "click-reset.png",
        lambda image: image.size == before.size and ImageChops.difference(before, image).getbbox() is None,
    )
    if args.close_method == "window":
        send_close(connection, window)
    else:
        send_key(connection, window, args.close_key)
    if process:
        assert process.wait(timeout=30) == 0, "Native app did not exit successfully"
    print(f"PASS native window, destruction ({differences} changed pixels), primary-click carving, background no-op, exact resets, {args.close_method} close")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", default="Bend Voxel Rewrite")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--destroy-key", default="space")
    parser.add_argument("--reset-key", default="r")
    parser.add_argument("--close-key", default="Escape")
    parser.add_argument("--close-method", choices=("escape", "window"), default="escape")
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--gpu", choices=("on", "off"), default="on")
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--tile-depth", type=int)
    parser.add_argument("--fork-depth", type=int)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    connection = display.Display()
    process = None
    log = None
    try:
        if args.binary:
            assert find_window(connection, args.title) is None, "Another slice window is already open"
            log = (args.output / "native-window.log").open("w")
            command = [str(args.binary.resolve()), "--gpu", args.gpu, "--threads", str(args.threads)]
            settings = []
            if args.tile_depth is not None:
                settings.extend(["--tile-depth", str(args.tile_depth)])
            if args.fork_depth is not None:
                settings.extend(["--fork-depth", str(args.fork_depth)])
            if settings:
                command.extend(["--", *settings])
            process = subprocess.Popen(
                command,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        check_window(args, connection, process)
    finally:
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        if log:
            log.close()
        connection.close()


if __name__ == "__main__":
    main()
