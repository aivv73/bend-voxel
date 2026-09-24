.PHONY: build run test benchmark-stress clean
build:
	./scripts/build.sh
run: build
	./scripts/run.sh
test:
	./scripts/test.sh
benchmark-stress: build
	python3 scripts/benchmark_stress.py
clean:
	rm -rf build
