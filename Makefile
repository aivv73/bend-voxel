.PHONY: build run test benchmark clean
build:
	./scripts/build.sh
run: build
	./scripts/run.sh
test:
	./scripts/test.sh
benchmark:
	./scripts/build.sh table-demo
	python3 scripts/benchmark.py
clean:
	rm -rf build

.PHONY: snapshots
snapshots:
	./scripts/build.sh snapshot
	python3 scripts/snapshot.py

.PHONY: compare-backends
compare-backends:
	./scripts/build.sh table-demo
	./scripts/build.sh snapshot
	python3 scripts/compare_backends.py $(COMPARE_ARGS)
