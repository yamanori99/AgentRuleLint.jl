# JAILint.jl

<!-- markdownlint-disable MD013 -->
[![Status](https://img.shields.io/badge/status-work_in_progress-orange?style=flat-square)](https://github.com/yamanori99/JAILint.jl)
[![Julia 1.13+](https://img.shields.io/badge/Julia-1.13+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://julialang.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
<!-- markdownlint-enable MD013 -->

**JAILint.jl** (Julia Agent Invariant Linter) is a static linter and
CI guardrail harness for Julia repositories developed with coding agents.
It enforces repository invariants and catches lint evasion, silent
fallbacks, and weakened tests.

## Status

Early development (not yet registered in General). The initial rule set
was brewed in [DistSSHRun.jl](https://github.com/yamanori99/DistSSHRun.jl)
and is being extracted into a standalone package.

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
