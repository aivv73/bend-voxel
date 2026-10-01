# Bend voxel rewrite

Run one editable 8³ voxel body in a native window. Destroy part of the body and inspect the newly exposed surfaces.

![Voxel body after destruction](docs/slice.png)

## Run the slice

Use Bend 2.0.34 or newer. Native GPU builds require the compiler and SDK for the available Bend execution lane. On Linux, install `libx11-dev` for the window.

```sh
	make
	make run
```

Use these controls:

- Press **Space** to remove a sphere near the visible front corner.
- Click a visible voxel with the primary mouse button to apply the same sphere brush at that voxel.
- Press **R** to restore the solid body.
- Press **Escape**, or close the window, to exit.

The image uses a fixed isometric camera. The brush removes cells within a radius of three cells. Repeating the same cut leaves the body unchanged.

To run on the CPU, disable GPU dispatch through Bend's runtime option:

```sh
	./build/bend-voxel-rewrite --gpu off
```

To require the available GPU lane, force GPU execution:

```sh
	./build/bend-voxel-rewrite --gpu on
```

Keep `build/bend-voxel-rewrite.gpu` beside the executable. On the development Linux machine, the CUDA SDK is at `/opt/cuda`. The Makefile detects that path at the build boundary. To use a different SDK path, set `CUDA_HOME`:

```sh
	make CUDA_HOME=/path/to/cuda
```

## Verify the slice

Run the formal laws, geometry reference cases, and complete CPU/GPU image comparisons:

```sh
	make test
```

The geometry reference check is written in Bend and compares complete cell and face sets, including materials. Run it separately with `make geometry`. The image checker and its parser and SHA-256 tests are also written in Bend. Run them with `make images`, or run only the parser and hash tests with `make image-unit`. Image checks force both `--gpu off` and `--gpu on` across four tile and fork configurations. The benchmark script requires Python 3 and its standard library.

To compare images on a machine without a GPU, run the CPU cases:

```sh
	make build/image-checker image-unit
	./build/image-checker --gpu off -- --cpu-only
```

The checker saves exports under `build/image-check`. It resolves the repository from its executable path, so absolute or relative invocations also work from another directory. If you invoke a bare executable name through `PATH`, supply `--root /path/to/repository`. Use `--binary path/to/renderer` to select another renderer. Relative renderer paths resolve under that root.

The parser accepts the renderer's unsigned ASCII P3 format with literal `P3 512 512 255` header tokens and exactly 786,432 channels in 0..255. ASCII whitespace and leading zeros in channels are accepted. PPM comments, signed values, digit underscores, and Unicode digits are rejected.

The native window check uses `Window.export_ref` from [the aivv73 Bend fork](https://github.com/aivv73/bend). Choose that compiler for the UI test. With the fork checked out beside this project, run:

```sh
	make ui UI_BEND='bun ../bend/bend2/main.ts'
	./build/ui-check --gpu off -- --output .audit/screenshots/cpu
	./build/ui-check --gpu on -- --close-method window --output .audit/screenshots/window-close
```

The GPU target saves native PPM screenshots in `.audit/screenshots/ui`. The CPU command saves them in `.audit/screenshots/cpu`.

The native check is written in Bend. It runs the slice's real view, event reducer, and `App.step`, exports the owned window after its first frames, and addresses that exact display and ID from a separate X11 connection. Existing slice windows may remain open. A small C effect adapter supplies native pixel capture and input; the assertions and screenshot export stay in Bend. The check requires X11 and `libX11`. Unsupported backends report an error.

The UI test was validated with fork commit `d24b7ecf5a3356f5522f5439daaa586b0ec0ba3f`, which includes the owned-window reference API. Its C adapter uses Bend runtime internals and must be rebuilt when changing compilers. Delete `build/ui-check` and its `.gpu` sibling before selecting a different `UI_BEND`. Read [the verification notes](docs/verification.md) for the scope of formal proofs and runtime checks.

## Export an image

Write the same rendered `Image` to a deterministic PPM file:

```sh
	./build/bend-voxel-rewrite --gpu on --dump build/full.ppm
	./build/bend-voxel-rewrite --gpu on --cut --dump build/destroyed.ppm
```

## Measure native frames

Measure displayed frames with cached scenes and scripted destruction and reset:

```sh
	make benchmark
```

The command records interleaved CPU and GPU measurements in `build/benchmark.json`. Each run excludes eight warm-up frames. CPU thread counts and GPU work decomposition are measured separately. The benchmark uses one thread, half the reported CPU cores, and all reported CPU cores. Override those counts with `scripts/benchmark.py --cpu-threads 1 4 8`.

To choose a work decomposition, set both depths:

```sh
	./build/bend-voxel-rewrite --gpu on --tile-depth 5 --fork-depth 5 --bench 120
```

The default tile and fork depths are both five. Native measurements selected that configuration for the available GPU lane.

`--tile-depth` chooses the tile tree depth within the 512-pixel image. `--fork-depth` chooses how many tile tree levels may fork. Both accept values from zero to nine. Leaves run sequentially. These settings change scheduling and candidate lists while preserving the pixels.

Read [the design notes](docs/design.md) for the data flow, boundaries, and examples considered.
