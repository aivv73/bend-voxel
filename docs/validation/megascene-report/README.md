# Issue #62 report verification

`python3 -m unittest discover -s tests -p 'test_megascene_report.py'` exercises
the accepted synthetic outcomes: static success, one-cut inconclusiveness, slow
history, required edit rejection, monitoring loss, reserve stop, explicit
allocation failure, missing GPU tail, rendering/quality failure, interruption,
calibration status/scope, malformed evidence and unsupported schemas. The
synthetic examples check report policy and do not establish Vulkan performance.

The [results](results.json) were produced through `report_bundle()` on retained
real static and localized archives. The older static archive has no GPU stream
or named quality assessment; the reader preserves its completed CPU prefix and
does not qualify it. The reviewed localized archive has separate validation,
checkpoints, GPU/resource evidence and a passing feature assessment. It yields
qualified capacity, while its one accepted edit and short measured interval
leave interactivity inconclusive. These are attempt observations, not confirmed
search endpoints. Archive paths in the results identify the retained source
bundles; this committed file is a concise index, not a reproduction bundle.

All state and native correctness claims here are runtime/reference checks.
Unsafe and native implementation behavior is outside Bend's formal proof scope.
