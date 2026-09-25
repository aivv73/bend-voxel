.PHONY: build run test benchmark-stress export-showcase-assets clean
build:
	./scripts/build.sh
run: build
	./scripts/run.sh
test:
	./scripts/test.sh
benchmark-stress: build
	python3 scripts/benchmark_stress.py
export-showcase-assets:
	blender -b assets/showcase_assets.blend --python scripts/export_showcase_assets.py
clean:
	rm -rf build
