---
name: rule-authoring
description: >
  Author or change AgentRuleLint rules: slug identity, intent, corpus, and Runic invariance.
  Use when adding rules, presets, or project-scoped checks.
---

# Rule authoring

## Identity

Canonical rule IDs are **kebab-case slugs only**:

- `<slug>`
- `<preset>/<slug>`
- `project/<slug>`

Never use numeric `JA*` or `JP*` codes. Never reuse a retired slug.

## Workflow (current tree)

One `RuleDef` per rule in `src/rules/<name>.jl`. Register it in the sorted
`RULE_DEFS` tuple in `src/rules/builtin_rules.jl` (explicit includes; no glob).
`intent` and `do_not` live **only** on that `RuleDef` (config may override at
load; explain parity is `test/test_rule_def_explain_parity.jl`). Completeness
(source, test, coverage paths) is `test/test_rule_registration.jl`.

Ship a **positive** corpus file and an **evasion** corpus file. Add a **mutation**
case that proves the detector is live (Pkg.test subprocess and/or
`test/mutation/`). Update Runic invariance in `test/test_runic_invariance.jl`
when formatting-sensitive behavior changes.

`do_not` names the **category** of forbidden action, not a list of bypass
techniques; technique lists belong in corpus files and test comments.

Rules are **pure functions**: no pull-request code execution, no `eval`, no I/O or git access inside rule logic.

`fix`, `may`, and `docs_url` are planned `RuleDef` fields in #110, not present today.

## Corpus

Golden examples must pass; adversarial examples must fail (concatenation, indirect names, comment tricks).

## Non-goals

Do not implement NG1–NG5 as rules. The definitions live only in
`CONTRIBUTING.md` (“Non-goals (NG1–NG5)”).

Before merging a new rule, read `AGENTS.md` and `CONTRIBUTING.md` when present on the branch.
