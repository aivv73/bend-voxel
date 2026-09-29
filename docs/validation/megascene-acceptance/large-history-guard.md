# Large-history action 5 guard regression

The first large-history/1-thread calibration validation in the retained
`/home/aivv/megascene-acceptance-68-retry` campaign stopped at frame 181,
action 5. Its worker reported `edit numeric guard: ID/motion/target` after five
accepted cuts. The attempt and a separate hashed copy of its partial work are
preserved under that campaign's `failed/history-large-1-validation-on` path.
The resource supervisor reported `worker_error`; its host and GPU monitoring
remained fresh, so this is a numeric admission failure.

The frozen action-5 target is `(-56.400001525878906, 7.203800201416016,
-46.0)` metres. The moved target body's Y offset is `-0.19620004296302795`
metres. Its Bend-local X coordinate rounds to `-564` cells in binary32, while
the guard's double expression is `-564.0000152587891`. The prior `0.00001`
cell agreement limit rejected that difference even though the same guard's
half-cell grid check already allowed `0.0001` cell. The target, geometry and
motion are unchanged. The double agreement limit now matches the existing
`0.0001` cell grid limit, and `tests/native_edit.cpp` records the exact failing
coordinate as a regression case. The subdivision predicate checks remain in
place for every visited leaf.

This numeric guard is runtime evidence around unsafe carving. Bend proof
results do not formally prove the unsafe carving or native Vulkan behavior.
