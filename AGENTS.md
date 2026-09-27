# Repository Instructions

## Documentation language

All project documentation must be written and maintained in English. This includes README files, architecture and research notes, domain glossaries, ADRs, agent instructions, and issue and pull request titles and descriptions. Keep existing documentation in English when editing it, and write all new documentation in English.

Conversation with the user may remain in their preferred language.

## Agent skills

### Issue tracker

Tasks and specifications are tracked in GitHub Issues in `aivv73/bend-voxel`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five standard triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: root `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.

Parallelism laws for bend-voxel:

- Independence alone is not sufficient reason to fork.
- Prefer sequential execution unless representative end-to-end benchmarks
  demonstrate a repeatable improvement.
- Benchmark candidate parallelism at 1, 6, and 12 threads.
- Validate candidates in real Vulkan workloads, not only headless benchmarks.
- Reject performance changes that alter observable world/geometry state.
- Keep fine-grained work sequential at leaves.