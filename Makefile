.PHONY: build run test proof proof-verdict test-blender benchmark-stress benchmark-faces export-atelier-assets clean
build:
	./scripts/build.sh
run: build
	./scripts/run.sh
test:
	./scripts/test.sh
proof:
	bash scripts/proof.sh
proof-verdict:
	bash scripts/proof.sh --verdict
test-blender:
	blender -b --factory-startup --python-exit-code 1 --python tests/blender_voxelize.py
benchmark-stress: build
	python3 scripts/benchmark_stress.py
benchmark-faces:
	./scripts/benchmark_faces.sh
export-atelier-assets:
	blender -b assets/light_atelier.blend --python-exit-code 1 --python scripts/export_atelier_assets.py
clean:
	rm -rf build
