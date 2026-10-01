BEND ?= bend
UI_BEND ?= $(BEND)
PYTHON ?= python3
CUDA_HOME ?= $(if $(wildcard /opt/cuda),/opt/cuda,$(if $(wildcard /usr/local/cuda),/usr/local/cuda,))
export CUDA_HOME

BINARY := build/bend-voxel-rewrite
SOURCES := main.bend voxel.bend render.bend dump.bend

.PHONY: all run proof test geometry image-unit images ui benchmark clean

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

build/ui-check: scripts/ui_check.bend scripts/ui_native.bend scripts/ui_native.c scripts/ui_native.js $(SOURCES) | build
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

ui: build/ui-check
	./build/ui-check --gpu on -- --output .audit/screenshots/ui

benchmark: $(BINARY)
	$(PYTHON) scripts/benchmark.py

test: proof geometry images

clean:
	rm -rf build
