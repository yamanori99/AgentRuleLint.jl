# AGENTS.md — AgentRuleLint.jl automation guide

Concise instructions for humans and coding agents working in this repository.

## 1. Core principles

AgentRuleLint is a **deterministic, fail-closed** Julia invariant linter. It does not execute PR code, does not call `eval`, does not use the network, and does not rely on type inference. Rules operate on parsed syntax and configured policy only.

Before fixing lint, test, or CI failures:

1. Read this file, `CONTRIBUTING.md`, and the rule’s `intent` / `do_not` (via `agentrulelint explain`).
2. Prefer a real fix over silencing output.
3. Do **not** weaken checks or reshape code solely to clear findings.

Invariants (one line each):

- Rule `intent` / `do_not` is defined once in the rule definition (guard: `test/test_rule_def_explain_parity.jl`).
- Formatters render the check result only and never read policy (guard: `test/test_formatter_policy_free.jl`).
- The package version is single-sourced from `Project.toml`.
- Tests never write into the repository tree; mutation assertions must fail, not pass, when a child process crashes.
- CLI options may change presentation only (color, width, a display cap with an always-printed omitted count). They never remove guidance an agent needs to act, and never change the verdict silently: a CLI override of a config value is stated in the verdict line. Anything that changes what is reported or how it is judged lives in the protected config file.
- Docs state only what is stable (purpose, install, exit codes, where to look), in short sentences without tables. Anything that can change (rules, levels, config keys, output fields) is discoverable from the tool (`explain`, schemas) and is not restated in prose.

## 2. Rule identity and admission

IDs are kebab-case slugs; presets are `<preset>/<slug>`; project rules are `project/<slug>`. Never reuse a retired slug. New rules need `intent`, `do_not`, corpus, and Runic invariance. Non-goals live only in `CONTRIBUTING.md`.

## 3. Architecture

One-way six-layer flow: **Entry → Types/Config → Syntax/Diff → Rules → Runner → Format**.

- Keep JuliaSyntax confined to `src/syntax/`.
- Rules stay pure: no I/O, no git calls inside rule bodies.
- Library code must not call `exit()`; the CLI is the only process exit.

## 4. Local verification before push

Run the commands in [`.agents/skills/pre-push-gate/SKILL.md`](.agents/skills/pre-push-gate/SKILL.md). Do not set `HOME` or `JULIA_DEPOT_PATH` persistently (per-command prefixes only).

## 5. Ceiling ratchet and `--diff`

See `agentrulelint --help` and `src/ratchet.jl`. Default `--diff` base is `HEAD^1`.

## 6. Hygiene

- Do not silently edit protected paths unless explicitly requested. Auto-protected paths: see `src/rules/protected_paths.jl`.
- When a change must edit protected paths and `protected-paths` will fail by design, follow the interim merge procedure in `CONTRIBUTING.md` (until #70). Agents never merge or approve those PRs.
- Merge `origin/main`; do not rebase or force-push this branch.
- Do not post GitHub comments, reviews, or merges directly.
