# AGENTS.md — JAILint.jl automation guide

Concise instructions for humans and coding agents working in this repository.

## 1. Core principles

JAILint is a **deterministic, fail-closed** Julia invariant linter. It does not execute PR code, does not call `eval`, does not use the network, and does not rely on type inference. Rules operate on parsed syntax and configured policy only.

Before fixing lint, test, or CI failures:

1. Read this file, `CONTRIBUTING.md`, and the rule’s `intent` / `do_not` in source or config.
2. Prefer a real fix over silencing output.
3. Do **not** weaken checks or reshape code solely to clear findings.

## 2. Rule identity and admission

Canonical **slug-only** rule IDs (no numeric `JA*` / `JP:` codes):

| Form | Example |
| --- | --- |
| Built-in `[JAILint]` | `expect-audit`, `protected-paths` |
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
JULIA_LOAD_PATH="@:@stdlib" julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
```

Confirm `Pkg.test()` runs **Aqua** and `test/test_runic_invariance.jl` and that they pass. Do not set `HOME` or `JULIA_DEPOT_PATH` persistently in the shell (per-command prefixes only).

## 5. Hygiene

- Do not silently edit protected policy/workflow files (`.JAILintConfig.toml`, `AGENTS.md`, `.github/workflows/**`) unless explicitly requested.
- Merge `origin/main`; do not rebase or force-push this branch.
- Do not post GitHub comments, reviews, or merges directly.
