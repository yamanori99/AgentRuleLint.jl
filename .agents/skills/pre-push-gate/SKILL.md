---
name: pre-push-gate
description: >
  Final-tree verification before push. Use when preparing a commit or pull request
  for AgentRuleLint.jl, or when asked to run the local agent gate.
---

# Pre-push gate

Run these on the exact tree you will push, with no further edits afterward.

## Always

1. `runic --check --diff .` using the pin in `.github/runic/Project.toml`.
2. Trailing-newline audit on all tracked text files (each file ends with a single newline).
3. `git diff --check` on the staged and unstaged diff you are about to push.
4. `./.github/jetls-check.sh` when that script exists and `src/AgentRuleLint.jl` and `test/runtests.jl` are present (added in the core foundation PR).

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

Confirm **Aqua** runs and `test/test_runic_invariance.jl` executes.

Check the command's exit status; a non-zero status means the suite failed, even if you only read the digest.

On failure, read the digest (`=== AgentRuleLint test failure digest ===` at the
end of the log, or `test/last_failures.txt`), or
`grep -n "Test Failed\|Error During Test" /tmp/agentrulelint-test.log`. Never
re-run the full suite only to see which tests failed. Re-run the affected group
(via test selection once it exists), then run the full suite once on the final
tree.

## Hygiene

- No `exit()` in library code (`src/`).
- Never persist `export HOME=` or `export JULIA_DEPOT_PATH=` in the shell profile; prefix per command only.
- Do not weaken a check or hollow a test to get green CI.

Install missing pinned apps only when the person asked (`./.github/install-agent-tools.sh`).
