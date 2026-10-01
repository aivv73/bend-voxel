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

The reference scripts require Python 3 and its standard library. Geometry checks compare complete cell and face sets. Image checks force both `--gpu off` and `--gpu on` across several work decompositions.

To compare images on a machine without a GPU, run the CPU cases:

```sh
	python3 scripts/image_check.py --cpu-only
```

To exercise the real native window on the development X11 display, run the input and screenshot check:

Close any existing slice window before this check.

```sh
	make ui
	python3 scripts/ui_check.py --binary build/bend-voxel-rewrite --gpu off --output .audit/screenshots/cpu
```

The GPU target saves screenshots in `.audit/screenshots/ui`. The CPU command saves them in `.audit/screenshots/cpu`.

The native check requires X11, `libX11`, ImageMagick's `import` command, Pillow, and python-xlib. Read [the verification notes](docs/verification.md) for the scope of formal proofs and runtime checks.

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
