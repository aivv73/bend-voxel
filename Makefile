BEND ?= bend
UI_BEND ?= $(BEND)
CUDA_HOME ?= $(if $(wildcard /opt/cuda),/opt/cuda,$(if $(wildcard /usr/local/cuda),/usr/local/cuda,))
export CUDA_HOME

BINARY := build/bend-voxel-rewrite
SOURCES := main.bend voxel.bend render.bend dump.bend

.PHONY: all run proof test geometry image-unit images ui ui-unit benchmark benchmark-unit clean

all: $(BINARY)

build:
	mkdir -p build

$(BINARY): $(SOURCES) | build
	$(BEND) main.bend -o $@

build/geometry-tests: tests.bend voxel.bend | build
	$(BEND) tests.bend -o $@

build/reference-check: scripts/reference_check.bend | build
	$(BEND) scripts/reference_check.bend -o $@

build/image-checker: scripts/image_check.bend scripts/image_data.bend scripts/sha256.bend | build
	$(BEND) scripts/image_check.bend -o $@

build/hash-tests: scripts/hash_tests.bend scripts/sha256.bend | build
	$(BEND) scripts/hash_tests.bend -o $@

build/image-tests: scripts/image_tests.bend scripts/image_data.bend scripts/sha256.bend | build
	$(BEND) scripts/image_tests.bend -o $@

build/benchmark: scripts/benchmark.bend scripts/benchmark_host.bend scripts/benchmark_number.bend scripts/sha256.bend | build
	$(BEND) scripts/benchmark.bend -o $@

build/benchmark-tests: scripts/benchmark_tests.bend scripts/benchmark.bend scripts/benchmark_host.bend scripts/benchmark_number.bend scripts/sha256.bend | build
	$(BEND) scripts/benchmark_tests.bend -o $@

build/benchmark-number-tests: scripts/benchmark_number_tests.bend scripts/benchmark_number.bend | build
	$(BEND) scripts/benchmark_number_tests.bend -o $@

build/ui-capture-tests: scripts/ui_capture_tests.bend scripts/ui_capture.bend | build
	$(UI_BEND) scripts/ui_capture_tests.bend -o $@

build/ui-check: scripts/ui_check.bend scripts/ui_capture.bend scripts/ui_native.bend scripts/ui_native.c scripts/ui_native.js $(SOURCES) | build
	$(UI_BEND) scripts/ui_check.bend -o $@

run: $(BINARY)
	./$(BINARY)

proof:
	$(BEND) PROOF.bend
	$(BEND) PROOF.bend --verdict

geometry: build/geometry-tests build/reference-check
	./build/reference-check --gpu off

image-unit: build/hash-tests build/image-tests
	./build/hash-tests --gpu off
	./build/image-tests --gpu off

images: $(BINARY) build/image-checker image-unit
	./build/image-checker --gpu off

ui-unit: build/ui-capture-tests
	./build/ui-capture-tests --gpu off

ui: build/ui-check ui-unit
	./build/ui-check --gpu on -- --output .audit/screenshots/ui

benchmark-unit: build/benchmark-tests build/benchmark-number-tests
	./build/benchmark-tests --gpu off
	./build/benchmark-number-tests --gpu off

benchmark: $(BINARY) build/benchmark
	./build/benchmark --gpu off

test: proof geometry images benchmark-unit

clean:
	rm -rf build
