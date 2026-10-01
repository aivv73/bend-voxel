# Slice verification

`make test` reruns the formal and headless runtime checks. `make ui UI_BEND='bun ../bend/bend2/main.ts'` verifies real native input and screenshots with the owned-window reference API. `make benchmark` measures native displayed frames.

## Formal scope

`LAWS.bend` states six local laws. `PROOF.bend` proves material erasure idempotence, preservation on a miss, removal on a hit, hidden faces, empty cells, and isolated solid faces. Geometry calls the proven erasure and face predicates.

Both `bend PROOF.bend` and `bend PROOF.bend --verdict` pass. These laws do not prove the complete body traversal, surface extraction, projection, native effects, or GPU runtime. Runtime tests cover those paths. No property that depends on an unsafe definition is claimed as formally proven.

## Geometry cases

`tests.bend` calls the actual body operations and surface extractor, then emits complete occupied cells and explicit faces. `scripts/reference_check.bend` launches that executable with GPU execution disabled and compares its output against an independent set translation reference. The checker imports only `Base`; it does not reuse engine geometry, indexing, or brush predicates. For each direction, it constructs the translated occupied set and takes the difference from the original set. A one-cell coordinate offset represents negative translations without unsigned wraparound.

`make geometry` compiles and runs both Bend programs. The check compares every occupied coordinate and material, every face direction and material, and the reported and emitted face counts. It also checks known surface counts, that the cut is a proper subset, and that repeating the cut preserves geometry. The parser rejects duplicate cells or cases, malformed records, missing counts, and unterminated cases; emitted face counts expose duplicate faces.

To check a saved candidate dump, run `./build/reference-check --gpu off -- --input path/to/dump.txt`. To select a candidate executable, use `--binary path/to/geometry-tests`. The default executable path is relative to the project root. Candidate runs have a 30-second timeout and a 1 MiB output limit. These geometry checks are runtime assertions, not formal proofs.

The checker passed all twelve cases on native CPU and Bun JavaScript execution, using the same native candidate executable. A tail-recursive line splitter handles the complete dump on both targets. Native execution also rejected twenty negative probes, covering changed materials, missing or duplicate faces, incorrect counts, malformed input, duplicate or missing cases, incomplete output, and a failed candidate process.

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

`scripts/ui_check.bend` opens the slice's native window and drives its actual view and reducer through `App.step`. It exports `X11WindowRef{display, id}` after the first frames. The test queries and sends input to that exact reference through a separate X11 connection; it never enumerates windows or matches titles. The owner is renamed during the test, and repeated exports must preserve its identity.

`scripts/ui_native.c` is the narrow OS boundary for native pixel capture, key and mouse events, close requests, and checking that the exported window has expired. It returns captured pixels as a Bend `Image`; Bend checks every pixel and writes PPM evidence. No Python, Pillow, ImageMagick, or python-xlib is used by the native check. The JavaScript adapter reports unsupported native X11 operations.

The test captures the client image before destruction, after Space, after repeating Space, after reset, and after primary-click carving. Space must change exactly 18,520 pixels; repeating it must preserve the image. Background clicks must preserve the image. Both resets must restore every pixel. Primary click must carve a different region from Space. Escape and the window close event must stop the actual app reducer, and the exported window must then be gone. A completion channel prevents an unexpected early Close from being counted as success.

The assertions are runtime checks. Native identity, capture, event delivery, and lifetime depend on foreign IO and are not claimed as formally proven. Compile and run the UI check; `--verdict` remains the gate for `PROOF.bend`'s six local laws.

The harness owns its window in the test process and imports the slice's shared view and reducer. It does not launch the standalone application binary. The development run passed CPU and GPU execution with both Escape and Close, and all seven captured states matched across the four runs. The full and destroyed captures also matched the existing renderer exports. An injected premature Close exited with status 1 without reporting success. The JavaScript adapter's unsupported path exited with status 95.

`make ui` checks Escape. To check the window close event, run the built test:

```sh
	./build/ui-check --gpu on -- --close-method window --output .audit/screenshots/window-close
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
