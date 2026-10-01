# Slice verification

`make test` reruns the formal and headless runtime checks. `make ui` verifies real native input and screenshots. `make benchmark` measures native displayed frames.

## Formal scope

`LAWS.bend` states six local laws. `PROOF.bend` proves material erasure idempotence, preservation on a miss, removal on a hit, hidden faces, empty cells, and isolated solid faces. Geometry calls the proven erasure and face predicates.

Both `bend PROOF.bend` and `bend PROOF.bend --verdict` pass. These laws do not prove the complete body traversal, surface extraction, projection, native effects, or GPU runtime. Runtime tests cover those paths. No property that depends on an unsafe definition is claimed as formally proven.

## Geometry cases

`tests.bend` calls the actual body operations and surface extractor, then emits complete occupied cells and explicit faces. `scripts/reference_check.py` compares those values against an independent set translation reference. It also rejects duplicate faces.

The checked results are below.

| Case | Occupied cells | Exposed faces |
| --- | ---: | ---: |
| Empty 4³ body | 0 | 0 |
| One material-7 cell | 1 | 6 |
| Two adjacent material-7 cells | 2 | 10 |
| Solid 4³ body | 64 | 96 |
| One interior cell removed | 63 | 102 |
| Repeated interior removal | 63 | 102 |
| Out-of-bounds writes | 1 | 6 |
| Far outside sphere on a solid 4³ body | 64 | 96 |
| Separate opposite-edge cells | 2 | 12 |
| Solid 8³ body | 512 | 384 |
| Front sphere removed | 446 | 396 |
| Repeated front sphere | 446 | 396 |

The far-sphere case guards unsigned distance overflow. Bounds and edge cases guard accidental index wrapping. Full occupancy comparisons require the destruction operation to preserve every cell outside the brush.

## Image and native checks

`scripts/image_check.py` compares every RGB word for the full and destroyed scenes. It runs the same executable with forced CPU and forced GPU execution at several tile and fork depths. It also checks known pixels and requires the front cut to change exactly 18,520 pixels.

`scripts/ui_check.py` sends native X11 input to the actual Bend window. It captures the client image before destruction, after Space, after reset, and after primary-click carving. Background clicks must preserve the image. Reset must restore identical pixels. Escape and the window close event must exit successfully.

`make ui` checks Escape. To check the window close event, run:

```sh
	python3 scripts/ui_check.py --binary build/bend-voxel-rewrite --gpu on --close-method window --output .audit/screenshots/window-close
```

The development machine exercised the current Linux GPU lane. Metal and future WebGPU lanes have not been tested in this slice. Core code uses Bend types and parallel calls rather than backend-specific operations.

## Native measurement

`--bench N` opens a native window and shows N measured frames after eight warm-up frames. The scripted workload destroys the front sphere and resets the body every 24 frames. The scene is cached between edits. Rendering, edit rebuilds, `Window.frame`, and the same image disposal used by `App.run` occur inside the measured interval.

`IO.now` reports milliseconds in Bend 2.0.34. The executable prints `elapsed_ms`. `scripts/benchmark.py` interleaves three runs in alternating configuration order and records median milliseconds per displayed frame. The development CPU configurations use one, six, and twelve threads. The script derives its defaults from the reported CPU core count and accepts `--cpu-threads` overrides. GPU configurations vary tile and fork depths independently of those CPU measurements.

New benchmark reports include the timestamp and SHA-256 hashes of the executable and its Bend sources.

Native display refresh can cap the observed CPU rate. This benchmark measures the complete slice rather than isolated GPU compute throughput.

The development run recorded these medians. Rerun `make benchmark` to regenerate the measurements for the available hardware and display.

| Execution | CPU threads | Tile depth | Fork depth | Median ms per displayed frame |
| --- | ---: | ---: | ---: | ---: |
| CPU | 1 | 6 | 0 | 19.375 |
| CPU | 1 | 6 | 6 | 19.167 |
| CPU | 6 | 6 | 6 | 16.708 |
| CPU | 12 | 6 | 6 | 16.708 |
| GPU | 1 | 4 | 0 | 858.833 |
| GPU | 1 | 4 | 4 | 46.500 |
| GPU | 1 | 5 | 5 | 16.708 |
| GPU | 1 | 6 | 6 | 16.708 |

The default uses tile depth five and fork depth five. That is the smallest tested GPU decomposition that reaches the display cadence. Depth six produces the same observed displayed rate with more tile tree nodes.
