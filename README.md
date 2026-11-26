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

## Planned scope

- **Anti-evasion checks**: catch constructed or split forbidden tokens,
  wrapper-hidden shell/process calls, and malformed or unapproved
  suppression comments.
- **Ratchets**: keep per-rule exception counts monotonic (down only).
- **Rule-change guards**: flag unapproved edits to lint rules, ceilings,
  or allowlists in diffs.
- **Test-strength checks**: detect weakened assertions, hollowed test
  inputs, and shrinking test coverage in diffs.
- **Local and CI modes**: run diff-scoped or full-repository checks in a
  single Julia process. `check` is reentrant: multiple threads or tasks may call
  it concurrently on the same process.

**In this dev tree:** built-in `expect-audit` and declarative
`[[project_rules]]` (`project/<id>`) are implemented; other built-in slugs
(e.g. `protected-paths`, `manifest-sync`) are roadmap.

## Setup for coding agents

Read [AGENTS.md](AGENTS.md) before changing rules or silencing diagnostics.
Further detail: [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
[LICENSE](LICENSE).

## Design (for developers)

### Repository layout

```text
src/                     # package sources and CLI (@main)
  AgentRuleLint.jl       # module entry, cli_main, check
  config.jl              # .AgentRuleLintConfig.toml loading
  diff.jl                # git diff scope
  expect.jl              # suppression comment parsing
  fingerprints.jl        # stable diagnostic fingerprints
  path_glob.jl           # project-rule path glob patterns → Regex
  runner.jl              # rule orchestration
  types.jl               # shared types
  format/                # human, JSON, agent output
  rules/                 # built-in and project rules
  syntax/                # JuliaSyntax adapter (no eval)
test/                    # Pkg.test suite
  Project.toml           # workspace test project (Aqua, Test)
  runtests.jl            # test entry
  test_*.jl              # focused tests
  corpus/                # golden regression fixtures
  runic_env/             # isolated Runic invariance env
scripts/                 # maintainer shell helpers
.github/                 # CI workflows and lint pins
.agents/                 # agent skill files (mirrored under .claude/, .cursor/)
.AgentRuleLintConfig.toml  # default rule policy for this repo
AGENTS.md                # agent automation guide
CONTRIBUTING.md          # contributor and issue workflow
SECURITY.md              # security and protected paths
Project.toml             # package metadata, [workspace], and [apps]
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
  and Runic invariance on the golden corpus under `test/corpus/`.
