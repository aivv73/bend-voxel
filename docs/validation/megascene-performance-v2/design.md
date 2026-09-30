# Performance protocol v2 design

The selected scopes are static and history at small, seed 45, six threads, full geometry, and 1920x1080. Both use 120 warmup and 21600 measured frames. Schedule IDs are `static-perf-v2` and `history-perf-v2`. Historical defaults and issue68 acceptance stay unchanged.

The data shape is the existing frozen frame array. Each frame declares a disjoint population and review/checkpoint selection. A small derived binary policy table carries phase and flags to the native recorder. The existing camera file stays intact. Admitted query-pair count and history overview frame travel in the archived worker environment. Native parsing bounds them. This keeps the current ABIs unchanged.

History uses 12 groups of 1800 frames. Action offsets are 0,180,360,540,720,732,1080,1260,1440,1620. Each group preserves the release-to-moving-target gap of 12 frames. All 120 cuts must remove their independent expected cells. Overall density is one cut per 180 measured frames. The final cut is ordinal 21420. Its normal 179-frame suffix contains the 120-frame overview transition. No elapsed-time pacing is allowed.

Non-edit frames with a changed fragment offset or nonzero fragment speed are motion. Other measured non-edit frames are ordinary. Edit takes precedence. Complete validation checks this partition against actual per-body motion. Ordinary calibration requires 1000 frames and ten seconds summed from ordinary frame intervals in every control. Combined wall duration is descriptive and separate.

The 21721 frame count sizes GPU query pairs and existing query indices. The common recorder reserves 21721 slots for static and 22081 for history, with equal reservation in both modes of each case. The bounded reference capacity becomes 32768 slots. The 21721-pair GPU limit prevents unrestricted allocation. The archive binds all derived input bytes and environment values to validation identity.

Two separate mode validations precede six fresh controls in `off,on,on,off,off,on` order for each selected case. Readers retain every calibration outcome. Three on observations provide repeatable canonical comparisons with the same validated runtime. The comparison command reports CPU frame/stage intervals, GPU submitted intervals, scripted edit response, ordinary/edit/motion populations, and sampled memory with its scope.

Three independent design candidates used the same inherited model. The cross-judge favored the indexed policy table. We grafted environment transport and observed-motion validation from the registry alternative. We rejected merging camera and checkpoint names into a new binary replay format. The smaller transport preserves the established replay paths.

The first full history validation stopped at the legacy300-second cap with18905 completed frames. Its failed prefix is retained. A separate480-second cap now applies only to full v2 history validation; timed workers, static and legacy remain bounded to300 seconds. The earlier campaign and reserve guards still apply.

Verification begins with historical schedule hashes and malformed-boundary tests. Complete real Vulkan validation and controls remain the performance evidence gate. Unsafe or native properties receive runtime/reference checks only.

## Principles and resulting choices

| Principle | Choice |
| --- | --- |
| Model the Domain | Frozen frame phases drive all v2 population readers. |
| Laziness Protocol | Keep camera transport and native ABIs. |
| Foundational Thinking | Fix admission and evidence shape before measuring. |
| Build the Lever | Deliver a rerunnable retained-series comparison command. |
| Prove It Works | Require actual Vulkan controls before claiming qualification. |
| Sequence work into verifiable units | Check historical hashes before wiring native consumers. |
| Separate Before Serializing Shared State | Keep separate candidate notes and one code owner; run Vulkan sequentially. |
| Never Block on the Human | Implement reversible protocol choices while retaining the explicit allowance gate. |
| Boundary Discipline | Reject mismatched counts and evidence identities at admission, native parsing and public readers. |
