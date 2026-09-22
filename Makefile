.PHONY: build run test benchmark clean
build:
	./scripts/build.sh
run: build
	./scripts/run.sh
test:
	./scripts/test.sh
benchmark: build
	python3 scripts/benchmark.py
clean:
	rm -rf build

.PHONY: snapshots
snapshots:
	./scripts/build.sh snapshot
	python3 scripts/snapshot.py
