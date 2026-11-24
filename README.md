# JAILint.jl

<!-- markdownlint-disable MD013 -->
[![Status](https://img.shields.io/badge/status-0.1.0--DEV-orange?style=flat-square)](https://github.com/yamanori99/JAILint.jl)
[![Julia 1.13+](https://img.shields.io/badge/Julia-1.13+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://julialang.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
<!-- markdownlint-enable MD013 -->

**JAILint.jl** (Julia Agent Invariant Linter) is a static linter and CI
guardrail harness for Julia repositories developed with coding agents. It
enforces repository invariants and catches shortcuts such as lint evasion,
silent fallbacks, and weakened tests.

> [!NOTE]
> **0.1.0-DEV** (not registered in General). Rules were first exercised in
> [DistSSHRun.jl](https://github.com/yamanori99/DistSSHRun.jl) and are being
> extracted into a standalone package.

## Quick start

```sh
git clone https://github.com/yamanori99/JAILint.jl "$HOME/JAILint.jl"
julia --project="$HOME/JAILint.jl" -e 'using Pkg; Pkg.instantiate()'

cd path/to/your/repo
julia --project="$HOME/JAILint.jl" -m JAILint check
julia --project="$HOME/JAILint.jl" -m JAILint check src
julia --project="$HOME/JAILint.jl" -m JAILint explain expect-audit
```

Place `.JAILintConfig.toml` at the repository root.

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
  single Julia process.

**In this dev tree:** built-in `expect-audit` and declarative
`[[project_rules]]` (`project/<id>`) are implemented; other built-in slugs
(e.g. `protected-paths`, `manifest-sync`) are roadmap.

## Setup for coding agents

Read [AGENTS.md](AGENTS.md) before changing rules or silencing diagnostics.
Further detail: [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
[LICENSE](LICENSE).

## Design (for developers)

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
