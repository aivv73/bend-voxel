#!/usr/bin/env python3
"""Make labelled contact sheets from immutable named review captures."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--rows", type=int, default=4)
    parser.add_argument("--tile-width", type=int, default=480)
    args = parser.parse_args()
    review = json.loads((args.bundle / "review.json").read_text())
    views = review["views"]
    if args.columns < 1 or args.rows < 1 or args.tile_width < 120 or not views:
        parser.error("positive grid and replay views required")
    tile_height = args.tile_width * 9 // 16
    label_height = 44
    args.output.mkdir(parents=True, exist_ok=False)
    entries = []
    page_size = args.columns * args.rows
    for start in range(0, len(views), page_size):
        sheet = Image.new("RGB", (args.columns * args.tile_width,
                                  args.rows * (tile_height + label_height)), "#ffffff")
        draw = ImageDraw.Draw(sheet)
        page = start // page_size + 1
        for index, view in enumerate(views[start:start + page_size]):
            capture = view["capture"]
            path = args.bundle / capture["path"]
            with Image.open(path) as source:
                thumbnail = source.convert("RGB").resize((args.tile_width, tile_height),
                                                         Image.Resampling.LANCZOS)
            x = (index % args.columns) * args.tile_width
            y = (index // args.columns) * (tile_height + label_height)
            sheet.paste(thumbnail, (x, y))
            draw.rectangle((x, y + tile_height, x + args.tile_width,
                            y + tile_height + label_height), fill="#142231")
            draw.text((x + 5, y + tile_height + 3),
                      f"{start + index + 1}: {view['name']}  frame {view['frame']}",
                      fill="white")
            draw.text((x + 5, y + tile_height + 20),
                      ", ".join(feature["name"] for feature in view["features"]),
                      fill="#d1dce6")
            entries.append({"view": view["name"], "frame": view["frame"],
                            "capture": capture["path"], "sha256": capture["sha256"],
                            "sheet": f"sheet-{page:02d}.png"})
        sheet.save(args.output / f"sheet-{page:02d}.png")
    (args.output / "index.json").write_text(json.dumps({
        "schema": "megascene-acceptance-contact-sheets/1",
        "bundle": str(args.bundle), "views": entries,
        "note": "Derived viewing aid; original captures and hashes are authoritative"},
        indent=2, sort_keys=True) + "\n")
    print(len(views), "views in", (len(views) + page_size - 1) // page_size, "sheets")


if __name__ == "__main__":
    main()
