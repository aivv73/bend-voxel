# Domain Docs

## Layout

This repository has a single context:

- Root `CONTEXT.md`: the domain glossary.
- `docs/adr/`: architecture decision records, created when needed.

## Before exploring

Read `CONTEXT.md` and the ADRs relevant to the task. If a root `CONTEXT-MAP.md` is introduced, follow its links to the relevant contexts and check their context-specific ADR directories as well.

If these documents do not exist, proceed silently. Do not flag their absence or suggest creating empty documents upfront. The `domain-modeling` skill creates them lazily as terms and decisions are resolved.

## Vocabulary

Use terms from `CONTEXT.md` in issue titles, proposals, code, hypotheses, and tests. Avoid synonyms that the glossary explicitly rejects.

If a concept is missing, reconsider whether the new terminology is needed; record genuine gaps for `domain-modeling`.

## ADR conflicts

When a proposal contradicts an existing ADR, identify the document and explain why the decision should be reconsidered rather than silently overriding it.

## Language

Maintain all domain documentation in English, including glossary definitions and ADRs.
