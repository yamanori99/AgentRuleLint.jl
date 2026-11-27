---
name: ci-and-lint-triage
description: >
  Fix CI or lint failures without weakening gates. Use when Actions lint, Runic,
  JETLS, or Pkg.test fails on a AgentRuleLint.jl change.
---

# CI and lint triage

## Before editing

1. Read `AGENTS.md` and `CONTRIBUTING.md` when they exist on your branch.
2. Read the rule source and `intent` for any diagnostic you are silencing.
3. Inspect the failure for evasion patterns (hidden expects, split strings, weakened asserts).

## Allowed fixes

- Correct the code to satisfy the invariant the check encodes.
- Fix pins only via `.github/runic/Project.toml`, `.github/jetls-rev`, and `.github/actions-lint.env`.
- Update tests and corpus when behavior intentionally changes.

## Forbidden shortcuts

- Do not weaken checks, ignore lists, or severity thresholds to go green.
- Do not weaken guard tests (explain parity, registration completeness, policy-free formatters).
- Do not delete or skip tests (including Aqua and Runic invariance) without an explicit product decision.
- Do not add blanket `continue-on-error` or hollow workflow steps.
- Do not reshape library code only to satisfy a linter without meeting intent.
- Do not pass CLI options to make a local run look green. The verdict that counts is CI’s, from the protected config.

## Workflow

Reproduce with the same command CI uses. Run `Pkg.test` with `set -o pipefail`
and `tee`; on failure read the digest instead of re-running the suite.
Fix the root cause, then run the full gate in [pre-push-gate](../pre-push-gate/SKILL.md).
