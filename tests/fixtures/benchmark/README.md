# Benchmark fixtures

Captured before deleting the benchmark Python paths from `fecd58d2`, using
Python 3.12.14. `ordinary`, `rounding` and `varying` contain fixed U32 profiler
words and the original parsers' exact cut/sample JSON. The initialization input
is 18014398509481985: it must be divided before rounding to F64. Full faces
report/stdout and parallel stdout/process traces were captured from the original
commands. The parallel report hashes cover the complete indent-2 JSON after
replacing the isolated fixture root with `@ROOT@`; runs 2 and 3 cover even/odd
medians, warmups, AB/BA order and 1/6/12 threads. These payloads are synthetic
correctness evidence, not performance measurements.

`decimal.tsv` retains independent Python float hex/repr pairs at the fixed and
scientific notation thresholds, rounding boundaries, subnormal and maximum F64
values. The Bend tests also assert literal compensated-sum/median bits, reject
malformed rows and retain the production schedule effect's nonfinite guards.
No expected value is calculated by the replacement statistics implementation.

The tiny shell fixtures emit recorded streams and trace process arguments,
directory and environment. They contain no geometry or metric oracle.
