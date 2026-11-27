# AGENTS.md — AgentRuleLint.jl automation guide

Concise instructions for humans and coding agents working in this repository.

## 1. Core principles

AgentRuleLint is a **deterministic, fail-closed** Julia invariant linter. It does not execute PR code, does not call `eval`, does not use the network, and does not rely on type inference. Rules operate on parsed syntax and configured policy only.

Before fixing lint, test, or CI failures:

1. Read this file, `CONTRIBUTING.md`, and the rule’s `intent` / `do_not` in source or config.
2. Prefer a real fix over silencing output.
3. Do **not** weaken checks or reshape code solely to clear findings.

## 2. Rule identity and admission

Canonical **slug-only** rule IDs (no numeric `JA*` / `JP:` codes):

| Form | Example |
| --- | --- |
| Built-in `[AgentRuleLint]` | `expect-audit`, `protected-paths` |
| Preset `[Preset]` | `shell-safety/process-pattern` |
| Project `[Project]` | `project/no-internal-codename` (declare `id = "no-internal-codename"` under `[[project_rules]]`) |

Retired IDs are never reused. New rules need `intent`, `do_not`, `fix` guidance, anchor semantics, golden and adversarial corpus entries, and Runic invariance. Non-goals **NG1–NG5** are in `CONTRIBUTING.md`.

## 3. Architecture and public API

One-way six-layer flow: **Entry → Types/Config → Syntax/Diff → Rules → Runner → Format**.

- Keep `JuliaSyntax` confined to `src/syntax/`.
- Rules stay pure: no I/O, no git calls inside rule bodies.
- Minimal exports: `check`, `CheckResult`, `Violation`, `RuleSpec` (plus typed errors and `Span`).
- Library code must not call `exit()`; CLI uses `cli_main` / `@main` only.

## 4. Local verification before push

Run on the final tree once, with no further edits after:

```bash
runic --check --diff .
# trailing newline on every tracked file
git ls-files -z | xargs -0 -I{} sh -c 'test -s "{}" && [ -n "$(tail -c1 "{}" | tr -d "\n")" ] && exit 1 || exit 0'
git diff --check
set -o pipefail; JULIA_LOAD_PATH="@:@stdlib" julia +1.13 --startup-file=no --project=. -e 'using Pkg; Pkg.test()' 2>&1 | tee /tmp/agentrulelint-test.log
```

Confirm `Pkg.test()` runs **Aqua** and `test/test_runic_invariance.jl` and that they pass. Do not set `HOME` or `JULIA_DEPOT_PATH` persistently in the shell (per-command prefixes only).

Check the command's exit status; a non-zero status means the suite failed, even if you only read the digest.

Always `tee` the suite as above. On failure, read the digest at the end of the
log or `test/last_failures.txt` (marker
`=== AgentRuleLint test failure digest ===`), or
`grep -n "Test Failed\|Error During Test" /tmp/agentrulelint-test.log`. Never
re-run the full suite only to see output. Re-run the affected group (via test
selection once it exists), then run the full suite once before pushing.

## 5. Ceiling ratchet and `--diff`

- **Full-repository `check` (no `--diff`)**: reads `.agentrulelint/ceilings.toml` from the working tree only. Compares live violation and expect counts against those ceilings (implicit ceiling `0` when a `(rule, path)` pair has no entry). Does **not** compare the ceilings file to a git base ref (local hand-edits are only fully enforced in diff-scoped CI).
- **`check --diff <base>`** (default base `HEAD^1`): loads ceilings from the working tree **and** from `<base>` via git. Fails if the file was removed relative to base, if any stored ceiling was raised, or if a new ceiling entry is greater than zero without a matching base entry. Unreadable base ceilings fail closed (exit `2`). Live counts are enforced against the working-tree ceilings when present, otherwise against the base file.
- **`ratchet --write` with `--diff` or path arguments**: merges counts for the scoped paths into the existing `.agentrulelint/ceilings.toml`; out-of-scope entries are preserved. A full-repository `ratchet --write` replaces the file from the scanned tree.

## 6. Hygiene

- Do not silently edit protected policy/workflow files (`.AgentRuleLintConfig.toml`, `AGENTS.md`, `.github/workflows/**`) unless explicitly requested.
- When a change must edit protected paths and `protected-paths` will fail by design, follow the interim merge procedure in `CONTRIBUTING.md` (until #70). Agents never merge or approve those PRs.
- Merge `origin/main`; do not rebase or force-push this branch.
- Do not post GitHub comments, reviews, or merges directly.
