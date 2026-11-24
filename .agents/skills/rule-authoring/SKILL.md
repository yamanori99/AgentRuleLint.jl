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

## Rule shape

Each rule documents:

- **intent** — what invariant it protects
- **do_not** — patterns and evasions that must fail
- **fix** — how to correct a violation
- **anchor line** — where diagnostics attach in source

Rules are **pure functions**: no pull-request code execution, no `eval`, no I/O or git access inside rule logic.

## Corpus

Ship **golden** (must pass) and **adversarial** (must fail) examples. Adversarial cases cover evasion patterns (concatenation, indirect names, comment tricks).

Add or update **Runic invariance** coverage in `test/test_runic_invariance.jl` when formatting-sensitive behavior changes.

## Non-goals (do not implement as rules)

| ID | Non-goal |
| --- | --- |
| NG1 | Runtime test execution inside the linter |
| NG2 | Network or registry access during `check` |
| NG3 | Mutating the repo or git state |
| NG4 | Executing user code from the PR diff |
| NG5 | Policy that belongs in CI shell gates instead of static rules |

Before merging a new rule, read `AGENTS.md` and `CONTRIBUTING.md` when present on the branch.
