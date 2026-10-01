BEND ?= bend
PYTHON ?= python3
CUDA_HOME ?= $(if $(wildcard /opt/cuda),/opt/cuda,$(if $(wildcard /usr/local/cuda),/usr/local/cuda,))
export CUDA_HOME

BINARY := build/bend-voxel-rewrite
SOURCES := main.bend voxel.bend render.bend dump.bend

.PHONY: all run proof test geometry images ui benchmark clean

all: $(BINARY)

build:
	mkdir -p build

$(BINARY): $(SOURCES) | build
	$(BEND) main.bend -o $@

build/geometry-tests: tests.bend voxel.bend | build
	$(BEND) tests.bend -o $@

run: $(BINARY)
	./$(BINARY)

proof:
	$(BEND) PROOF.bend
	$(BEND) PROOF.bend --verdict

geometry: build/geometry-tests
	$(PYTHON) scripts/reference_check.py

images: $(BINARY)
	$(PYTHON) scripts/image_check.py

ui: $(BINARY)
	$(PYTHON) scripts/ui_check.py --binary $(BINARY) --gpu on --output .audit/screenshots/ui

benchmark: $(BINARY)
	$(PYTHON) scripts/benchmark.py

test: proof geometry images

clean:
	rm -rf build
