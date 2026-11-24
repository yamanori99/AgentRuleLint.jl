# JAILint.jl

<!-- markdownlint-disable MD013 -->
[![Status](https://img.shields.io/badge/status-work_in_progress-orange?style=flat-square)](https://github.com/yamanori99/JAILint.jl)
[![Julia 1.13+](https://img.shields.io/badge/Julia-1.13+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://julialang.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
<!-- markdownlint-enable MD013 -->

**JAILint.jl** (Julia Agent Invariant Linter) is a static linter and
CI guardrail harness for Julia repositories developed with coding agents.
It enforces repository invariants and catches shortcuts such as lint
evasion, silent fallbacks, and weakened tests.

> [!NOTE]
> Early development (not registered in General). The initial rule set
> was brewed in [DistSSHRun.jl](https://github.com/yamanori99/DistSSHRun.jl)
> and is being extracted into a standalone package.

## Planned scope

- **Anti-evasion checks**: catch constructed or split forbidden tokens,
  wrapper-hidden shell/process calls, and malformed or unapproved
  suppression comments.
- **Ratchets**: keep per-rule exception counts monotonic (down only).
- **Rule-change guards**: flag unapproved edits to lint rules,
  ceilings, or allowlists in diffs.
- **Test-strength checks**: detect weakened assertions, hollowed test
  inputs, and shrinking test coverage in diffs.
- **Local and CI modes**: run diff-scoped or full-repository checks in
  a single Julia process.

## Setup for coding agents

```text
TODO: copy-paste setup prompt for coding agents (to be added once the CLI and config format settle).
```

## Design (for developers)

- **Fail-closed**: malformed suppression comments, unknown options, or
  broken rule state fail the check instead of silently passing.
- **Syntax over regex**: inspect parsed Julia syntax with lightweight
  constant folding rather than brittle text patterns, without requiring
  full type inference.
- **Assume evasion**: rules are written to catch surface-level workarounds
  such as split literals, wrapper indirection, or weakened tests, not
  only accidental mistakes.
- **Monotonic ratchets**: legacy debt is capped by tight per-rule
  ceilings that only go down; loosening a rule or ceiling requires
  explicit review.
- **Fast and self-tested**: runs in a single Julia process for local
  pre-push and CI, with self-tests verifying that every rule still fires
  on real violations.
