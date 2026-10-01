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

`scripts/image_check.bend` runs the native renderer with one thread, first for the full scene and then for the destroyed scene. Each scene visits GPU off and strict GPU on at tile and fork depths 4/0, 4/4, 5/5, and 6/6. The default runs sixteen exports. `--cpu-only` runs eight. The checker saves the existing deterministic filenames under `build/image-check` and uses the first image for each scene as its baseline.

`scripts/image_data.bend` retains baseline pixels as packed RGB lists and streams each later candidate against its baseline. Equality compares every channel through byte-equivalent packing, independently of SHA-256. The checker requires full-scene samples `(16,24,32)`, `(229,188,122)`, and `(160,114,72)` at `(0,0)`, `(256,256)`, and `(256,300)`. It counts each changed pixel once and requires exactly 18,520 changes.

The parser accepts unsigned ASCII P3 exports with the literal header tokens `P3`, `512`, `512`, and `255`, followed by exactly 786,432 channels in 0..255. ASCII whitespace and leading channel zeros are accepted. Comments, signs, digit underscores, Unicode digits, truncation, and extra channels are rejected. The reader scans bounded chunks, continues after nonempty short reads, checks progress against the file's reported size, and probes actual EOF. It adds no arbitrary file-size cap. Base's `File.size` rejects files larger than its U32 size range.

`scripts/sha256.bend` hashes the validated RGB channel bytes of the two retained baselines. It excludes the PPM header and whitespace. The full and destroyed digests are `a259f628eaeb04b707de9e5dc960eca4d80007fba2530beb96786cbca7b14a9b` and `4071d9e26a5a50cf429d4f65c6392fa679d784c2b7671933d4a9f4209e11b49d`. Hashes are reports. Exact equality and scene checks determine success.

`make image-unit` runs separate SHA vector and image parser executables. The parser tests drive fragmented header and channel tokens, literal short-read offsets and premature EOF, and the EOF boundary's rejection of an unread suffix. Fourteen malformed real files must fail with their specific header, channel, or count error under normal and one-byte reads. Complete images exercise 257-byte reads, coordinate bounds, an exact two-pixel delta, leading channel zeros, the final token without whitespace, and an extra-channel suffix. `make images` runs these tests before the renderer matrix. To inspect an existing file, run `./build/image-tests --gpu off -- --input path/to/image.ppm`. Add `--compare path/to/other.ppm` for exact comparison or `--chunk 257` to split input reads.

The checker derives its root from its executable directory's parent. Absolute or relative executable paths work outside the repository. Bare `PATH` invocation requires `--root repository`. `--binary renderer` accepts absolute paths or paths under that root. Child processes have a 180-second timeout and a 16 MiB combined stdout and stderr limit. Directory setup uses a checked direct `mkdir` call with a 30-second timeout. File and process failures stop the check before a successful report.

The native sixteen-export report and all sixteen raw PPM files matched the recorded Python baseline. Native CPU-only execution from the build directory and Bun JavaScript CPU-only execution from another directory also matched the expected eight-export report. Parser fixtures passed on native CPU and Bun JavaScript. SHA-256, image parsing, equality, and foreign IO receive runtime checks. No formal SHA or parser proof is claimed.

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
