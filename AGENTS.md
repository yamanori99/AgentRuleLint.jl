# AGENTS.md — AgentRuleLint.jl automation guide

Concise instructions for humans and coding agents working in this repository.

## 1. Core principles

AgentRuleLint is a **deterministic, fail-closed** Julia invariant linter. It does not execute PR code, does not call `eval`, does not use the network, and does not rely on type inference. Rules operate on parsed syntax and configured policy only.

Before fixing lint, test, or CI failures:

1. Read this file, `CONTRIBUTING.md`, and the rule’s `intent` / `do_not` in its `RuleDef`.
2. Prefer a real fix over silencing output.
3. Do **not** weaken checks or reshape code solely to clear findings.

Invariants (one line each):

- Rule `intent` / `do_not` is defined once in the `RuleDef` (guard: `test/test_rule_def_explain_parity.jl`).
- Formatters render `CheckResult` only and never read policy (guard: `test/test_formatter_policy_free.jl`).
- Package version is single-sourced from `Project.toml` (`AGENTRULELINT_VERSION = pkgversion(@__MODULE__)`).
- Tests never write into the repository tree; mutation assertions must fail, not pass, when a child process crashes (`test/mutation/mutation_lib.jl`, `test/mutation_subprocess_helpers.jl`).
- CLI options may change presentation only (color, width, a display cap with an always-printed omitted count). They never remove guidance an agent needs to act, and never change the verdict silently: a CLI override of a config value is stated in the verdict line. Anything that changes what is reported or how it is judged lives in the protected config file.

## 2. Rule identity and admission

Canonical **slug-only** rule IDs (no numeric `JA*` / `JP:` codes):

| Form | Example |
| --- | --- |
| Built-in `[AgentRuleLint]` | `expect-audit`, `protected-paths` |
| Preset `[Preset]` | `shell-safety/process-pattern` |
| Project `[Project]` | `project/no-internal-codename` (declare `id = "no-internal-codename"` under `[[project_rules]]`) |

Retired IDs are never reused. New rules need `intent`, `do_not`, anchor semantics, golden and adversarial corpus entries, and Runic invariance. Non-goals **NG1–NG5** live only in `CONTRIBUTING.md`.

## 3. Architecture and public API

One-way six-layer flow: **Entry → Types/Config → Syntax/Diff → Rules → Runner → Format**.

- Keep `JuliaSyntax` confined to `src/syntax/`.
- Rules stay pure: no I/O, no git calls inside rule bodies.
- Exports from `src/AgentRuleLint.jl`: `check`, `CheckResult`, `RuleSpec`, `Span`, `Violation`, `ConfigError`, `GitError`, `InternalError`, `ParseError` (`ParseError` rename is #52).
- Library code must not call `exit()`; CLI uses `cli_main` / `@main` only.

## 4. Local verification before push

Canonical commands: [`.agents/skills/pre-push-gate/SKILL.md`](.agents/skills/pre-push-gate/SKILL.md) (Julia **`+1.13`**). Summarized: Runic `--check --diff .`; trailing-newline audit; `git diff --check`; `./.github/jetls-check.sh` (`jetls check --exit-severity=hint`); `Pkg.test()` with `set -o pipefail` and `tee`; `julia +1.13 --startup-file=no --project=. test/mutation/run_all.jl` (all PASS); `git merge-tree --write-tree origin/main HEAD` clean.

On `Pkg.test` failure, read the digest (`=== AgentRuleLint test failure digest ===` or `test/last_failures.txt`); do not re-run the full suite only to see which tests failed. Re-run the affected file, then the full suite once on the final tree.

Do not set `HOME` or `JULIA_DEPOT_PATH` persistently (per-command prefixes only). Agents: `agentrulelint check --format agent`.

## 5. Ceiling ratchet and `--diff`

- **Full-repository `check` (no `--diff`)**: reads `.agentrulelint/ceilings.toml` from the working tree only. Compares live violation and expect counts against those ceilings (implicit ceiling `0` when a `(rule, path)` pair has no entry). Does **not** compare the ceilings file to a git base ref (local hand-edits are only fully enforced in diff-scoped CI).
- **`check --diff <base>`** (default base `HEAD^1`, `DEFAULT_DIFF_BASE` in `src/diff.jl`): loads ceilings from the working tree **and** from `<base>` via git. Fails if the file was removed relative to base, if any stored ceiling was raised, or if a new ceiling entry is greater than zero without a matching base entry. Unreadable base ceilings fail closed (exit `2`). Live counts are enforced against the working-tree ceilings when present, otherwise against the base file (`src/runner.jl`, `src/ratchet.jl`).
- **`ratchet --write` with `--diff` or path arguments**: merges counts for the scoped paths into the existing `.agentrulelint/ceilings.toml`; out-of-scope entries are preserved. A full-repository `ratchet --write` replaces the file from the scanned tree.

## 6. Hygiene

- Do not silently edit protected paths unless explicitly requested. Auto-protected (`AUTO_PROTECTED_EXACT` and helpers in `src/rules/protected_paths.jl`): `.AgentRuleLintConfig.toml`; `.agentrulelint/**` except a monotonic `.agentrulelint/ceilings.toml`; `.JETLSConfig.toml`; `Manifest*.toml`; `JuliaManifest.toml`; `LocalPreferences.toml`; every `Project.toml`; plus `[rules.protected-paths]` globs. Treat `AGENTS.md` as protected even if the dogfood config has not declared a glob for it.
- When a change must edit protected paths and `protected-paths` will fail by design, follow the interim merge procedure in `CONTRIBUTING.md` (until #70). Agents never merge or approve those PRs.
- Merge `origin/main`; do not rebase or force-push this branch.
- Do not post GitHub comments, reviews, or merges directly.
