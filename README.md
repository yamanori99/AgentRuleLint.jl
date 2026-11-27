# AgentRuleLint.jl

<!-- markdownlint-disable MD013 -->
[![Status](https://img.shields.io/badge/status-0.1.0--DEV-orange?style=flat-square)](https://github.com/yamanori99/AgentRuleLint.jl)
[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/AgentRuleLint.jl/CI.yml?branch=main&style=flat-square&logo=githubactions&logoColor=white&label=Test)](https://github.com/yamanori99/AgentRuleLint.jl/actions/workflows/CI.yml)
[![Codecov](https://img.shields.io/codecov/c/github/yamanori99/AgentRuleLint.jl?style=flat-square&logo=codecov&logoColor=white)](https://codecov.io/gh/yamanori99/AgentRuleLint.jl)
[![Julia 1.13+](https://img.shields.io/badge/Julia-1.13+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://julialang.org/)
[![code style: runic](https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black)](https://github.com/fredrikekre/Runic.jl)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
<!-- markdownlint-enable MD013 -->

**AgentRuleLint.jl** is a static linter and CI guardrail harness for Julia
repositories worked on with AI coding agents. It enforces invariants and agent
policy rules, and catches shortcuts such as lint evasion, silent fallbacks, and
weakened tests.

> [!NOTE]
> **0.1.0-DEV** (not registered in General). Rules were first exercised in
> [DistSSHRun.jl](https://github.com/yamanori99/DistSSHRun.jl) and are being
> extracted into a standalone package.

## Quick start

```sh
julia -e 'using Pkg; Pkg.Apps.add(url="https://github.com/yamanori99/AgentRuleLint.jl")'

cd path/to/your/repo
agentrulelint check
agentrulelint check src
agentrulelint explain expect-audit
```

Assuming `~/.julia/bin` is in your `PATH` you can invoke `agentrulelint` from
your shell (or `pkg> app add https://github.com/yamanori99/AgentRuleLint.jl` in
the Pkg REPL).

Place `.AgentRuleLintConfig.toml` at the repository root.
`unsafe-boundary` is enabled only by `[rules.unsafe-boundary]` (default `warn`).
`presets = ["unsafe-boundary/strict"]` flags `@inbounds` / `@generated` /
`@assume_effects`; it does not turn on core `unsafe-boundary`.

With a config file, `_inject_builtin_rules!` always adds `analysis-incomplete`,
`protected-paths`, `ceiling-ratchet`, and `scope-paths`. `expect-audit`,
`manifest-sync`, and `silent-catch` are in `default_policy` only when **no**
config exists; with a config they must be listed (`[rules.<id>]`).
`silent-catch` / `manifest-sync` do not run unless listed. `expect-audit` is
omitted from `policy.rules` unless listed, but comment-audit still runs at
`:forbid` when the table is missing (#28 Phase 3).

## Built-in rules and presets

From `RULE_DEFS`, `default_policy`, `_inject_builtin_rules!`, and
`KNOWN_PRESET_NAMES`:

| id | default | enabled |
| --- | --- | --- |
| `analysis-incomplete` | forbid | always (injected if omitted) |
| `ceiling-ratchet` | forbid | always (injected) |
| `protected-paths` | forbid | always (injected) |
| `scope-paths` | forbid | always (injected) |
| `expect-audit` | forbid | no-config default; with config, list `[rules.expect-audit]` (see gap above) |
| `silent-catch` | warn | no-config default; with config, `[rules.silent-catch]` |
| `manifest-sync` | deny | no-config default; with config, `[rules.manifest-sync]` |
| `test-integrity` | deny | `[rules.test-integrity]` only (not in `default_policy`) |
| `unsafe-boundary` | warn | `[rules.unsafe-boundary]` only |
| `shell-safety/process-pattern` | deny | `presets = ["shell-safety"]` |
| `unsafe-boundary/strict` | warn | `presets = ["unsafe-boundary/strict"]` |

Levels `forbid`, `deny`, and `warn` count as hits and set exit **1** (`warn`
included, as in JETLS). `allow` does not. Config/usage errors exit **2**.
Internal errors exit **3**.

Coding agents should run `agentrulelint check --format agent`.

Planned: output redesign and schema contract (#110, #111, #104, #105).

## Setup for coding agents

Read [AGENTS.md](AGENTS.md) before changing rules or silencing diagnostics.
Further detail: [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
[LICENSE](LICENSE). Local gate commands:
[`.agents/skills/pre-push-gate/SKILL.md`](.agents/skills/pre-push-gate/SKILL.md).

## Design (for developers)

### Repository layout

```text
src/          # CLI (@main), config, diff, expect, fingerprints, runner, types
  format/     # human, JSON, agent
  rules/      # one file per built-in/preset rule (+ registry helpers)
  syntax/     # JuliaSyntax adapter (no eval)
test/         # Pkg.test, corpus/, runic_env/, mutation/
docs/         # format notes (json-output.md)
schemas/      # JSONL schema (not yet the SemVer contract; #111)
NEWS.md       # user-facing changelog
.github/      # CI workflows and lint pins
.agents/      # skills (mirrored under .claude/skills only; .cursor/ has none)
.AgentRuleLintConfig.toml  AGENTS.md  CONTRIBUTING.md  SECURITY.md  Project.toml
```

- **Fail-closed**: malformed suppression comments, unknown options, or broken
  rule state fail the check instead of silently passing.
- **Syntax over regex**: inspect parsed Julia syntax with lightweight constant
  folding rather than brittle text patterns, without full type inference.
- **Assume evasion**: rules target surface-level workarounds (split literals,
  wrapper indirection, weakened tests), not only accidental mistakes.
- **Monotonic ratchets**: legacy debt is capped by per-rule ceilings that only
  go down; loosening requires explicit review.
- **Fast and self-tested**: single-process local and CI runs; tests include Aqua
  and Runic invariance on the golden corpus under `test/corpus/`. `check` is
  reentrant across threads/tasks.
