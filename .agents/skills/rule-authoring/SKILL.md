---
name: rule-authoring
description: >
  Author or change AgentRuleLint rules: slug identity, intent, corpus, and Runic invariance.
  Use when adding rules, presets, or project-scoped checks.
---

# Rule authoring

IDs are kebab-case slugs, `<preset>/<slug>`, or `project/<slug>`. Never reuse a retired slug.

One file per rule under `src/rules/`. Register it sorted by id in
`src/rules/builtin_rules.jl`. `intent` and `do_not` live only in that definition
(guards: `test/test_rule_def_explain_parity.jl`, `test/test_rule_registration.jl`).

`do_not` names the category of forbidden action, not a list of bypass
techniques. Technique lists belong in corpus files and test comments.

Ship a positive corpus file and an evasion corpus file. Add a mutation case
that proves the detector is live. Update Runic invariance when formatting-sensitive
behavior changes.

Rules are pure: no pull-request code execution, no `eval`, no I/O or git inside
rule logic.

Non-goals: `CONTRIBUTING.md` (“Non-goals (NG1–NG5)”).
Read `AGENTS.md` before merging a new rule.
