---
name: pre-push-gate
description: >
  Final-tree verification before push. Use when preparing a commit or pull request
  for AgentRuleLint.jl, or when asked to run the local agent gate.
---

# Pre-push gate

Single source for the local gate (`AGENTS.md` §4 and the PR template summarize).
Run on the exact tree you will push, Julia **`+1.13`**, no further edits after.

## Always

1. `runic --check --diff .` using the pin in `.github/runic/Project.toml`.
2. Trailing-newline audit on all tracked text files (each file ends with a single newline).
3. `git diff --check` on the staged and unstaged diff you are about to push.
4. `./.github/jetls-check.sh` (`jetls check --exit-severity=hint --show-severity=hint` on `src/AgentRuleLint.jl` and `test/runtests.jl`).
5. `git merge-tree --write-tree origin/main HEAD` must succeed with a clean tree.

## When scripts or workflows change

Run on all touched `.sh` files and workflow YAML:

- `shellcheck`
- `actionlint`
- `pinact run --fix=false --no-api`
- `zizmor --offline --no-progress` on changed workflow paths

Read `.github/actions-lint.env` and pin sources before bumping tool versions.

## When the package tree exists

```bash
set -o pipefail; JULIA_LOAD_PATH="@:@stdlib" julia +1.13 --startup-file=no --project=. -e 'using Pkg; Pkg.test()' 2>&1 | tee /tmp/agentrulelint-test.log
```

Confirm **Aqua** and `test/test_runic_invariance.jl`. The command’s exit status
is the suite result. Then:

```bash
JULIA_LOAD_PATH="@:@stdlib" julia +1.13 --startup-file=no --project=. test/mutation/run_all.jl
```

Every harness must **PASS** (nonzero or crash is failure).

On `Pkg.test` failure, read the digest (`=== AgentRuleLint test failure digest ===`
at the end of the log, or `test/last_failures.txt`). Never re-run the full suite
only to see which tests failed. Re-run the affected file, then the full suite once
on the final tree.

## Hygiene

- No `exit()` in library code (`src/`).
- Never persist `export HOME=` or `export JULIA_DEPOT_PATH=` in the shell profile; prefix per command only.
- Do not weaken a check or hollow a test to get green CI.

Install missing pinned apps only when the person asked (`./.github/install-agent-tools.sh`).
