---
name: ci-and-lint-triage
description: >
  Fix CI or lint failures without weakening gates. Use when Actions lint, Runic,
  JETLS, or Pkg.test fails on a AgentRuleLint.jl change.
---

# CI and lint triage

## Before editing

1. Read `AGENTS.md` and `CONTRIBUTING.md` when they exist on your branch.
2. Read the **rule source** and documented **intent** for any diagnostic you are silencing.
3. Inspect the failure output for **evasion patterns** (hidden expects, split strings, weakened asserts).

## Allowed fixes

- Correct the code to satisfy the invariant the check encodes.
- Fix pins only via the canonical files (`.github/runic/Project.toml`, `.github/jetls-rev`; workflow tools in `.github/actions-lint.env`).
- Update tests and corpus when behavior intentionally changes.

## Forbidden shortcuts

- Do not weaken checks, ignore lists, or severity thresholds to go green.
- Do not weaken guard tests (explain parity, registration completeness, policy-free formatters) to go green.
- Do not delete or skip tests (including Aqua and Runic invariance) without an explicit product decision.
- Do not add blanket `continue-on-error` or hollow workflow steps.
- Do not reshape library code only to satisfy a linter without meeting intent.
- Do not pass CLI options (for example a raised `--exit-severity`) to make a local run look green; the verdict that counts is CI’s, from the protected config.

## Workflow

1. Reproduce locally with the same command CI uses (see `.github/workflows/` and [pre-push-gate](../pre-push-gate/SKILL.md)).
2. Run the suite with `set -o pipefail` and `tee`; on failure read the digest (`test/last_failures.txt` or the log marker). Do not re-run the full suite only to see output.
3. Fix root cause; commit. Re-run the full pre-push gate on the final tree.

When unsure whether a failure reflects a bug in the gate or in the change, prefer fixing the change unless the gate contradicts written intent in `AGENTS.md`.
