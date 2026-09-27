.PHONY: build run test test-blender benchmark-stress benchmark-faces export-showcase-assets export-atelier-assets clean
build:
	./scripts/build.sh
run: build
	./scripts/run.sh
test:
	./scripts/test.sh
test-blender:
	blender -b --factory-startup --python-exit-code 1 --python tests/blender_voxelize.py
benchmark-stress: build
	python3 scripts/benchmark_stress.py
benchmark-faces:
	python3 scripts/benchmark_faces.py
export-showcase-assets:
	blender -b assets/showcase_assets.blend --python-exit-code 1 --python scripts/export_showcase_assets.py
export-atelier-assets:
	blender -b assets/light_atelier.blend --python-exit-code 1 --python scripts/export_showcase_assets.py -- --output src/atelier_assets.bend
clean:
	rm -rf build
