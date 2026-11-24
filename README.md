# JAILint.jl

<!-- markdownlint-disable MD013 -->
[![Status](https://img.shields.io/badge/status-0.1.0--DEV-orange?style=flat-square)](https://github.com/yamanori99/JAILint.jl)
[![Julia 1.13+](https://img.shields.io/badge/Julia-1.13+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://julialang.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
<!-- markdownlint-enable MD013 -->

**JAILint.jl** (Julia Agent Invariant Linter) is a static linter and CI
guardrail harness for Julia repositories developed with coding agents. It
encodes repository invariants—protected config, manifest integrity, test
strength, explicit boundaries—and communicates **design intent** in a
machine-readable form (`intent` / `do_not`) so humans and agents can align on
*what good looks like*.

> [!NOTE]
> Version **0.1.0-DEV** (not registered in General). Rules were first battle-tested in
> [DistSSHRun.jl](https://github.com/yamanori99/DistSSHRun.jl) and are being extracted
> into a standalone package.

## Philosophy: constructive guidance, not adversarial policing

JAILint is **not** an arms race against agents or contributors. It does not
replace code review, hunt for “gotchas,” or duplicate work that belongs to
formatters and type checkers. Instead it:

- **Teaches invariants** through `intent` and `do_not` text on every rule, so
  fixes improve understanding—not just silence diagnostics.
- **Complements** Runic, JETLS, Aqua, ExplicitImports, and CodeRabbit (see
  [ecosystem table](#ecosystem-boundary-non-interference)) instead of
  re-implementing their checks.
- **Fails closed on policy mistakes** (broken config, malformed
  `# jailint-expect:`) while treating new rule hits as actionable feedback, not
  moral failure.
- **Uses syntax-aware analysis** (JuliaSyntax, constant folding) to catch
  structural evasions where they matter, without regex vendettas on style.

Guardrails exist so agents write **better Julia**, not so maintainers win an
editing contest.

## Quick start

```bash
julia --startup-file=no --project=. -m JAILint check
julia --startup-file=no --project=. -m JAILint check src --format=agent
julia --startup-file=no --project=. -m JAILint explain expect-audit
```

Place `.JAILintConfig.toml` at the repository root (see
[configuration](#configuration)). Optional ceilings live in
`.jailint/ceilings.toml` and are updated only via `jailint ratchet --write`.

## CLI overview (0.1.0-DEV)

| Command | Purpose |
| --- | --- |
| `check [paths...]` | Run rules on paths or the whole tree (or diff-scoped files with `--diff`) |
| `explain <rule-id>` | Human-readable rule documentation (e.g. `expect-audit`, `project/foo`) |
| `ratchet --write` | Persist violation counts to `.jailint/ceilings.toml` after review |
| `report <fingerprint>` | Offline anonymized reproduction bundle (`header`, `rule_id`, `pattern_hash`) |

| Option | Values / notes |
| --- | --- |
| `--format` | `human` (default), `agent` (token-frugal for LLMs), `json` (3-record JSONL) |
| `--diff BASE` | Limit changed `.jl` files vs a git base |
| `--config PATH` | Alternate `.JAILintConfig.toml` |
| `--config-from REF` | Load policy from `git show REF:.JAILintConfig.toml` (strict CI mode) |
| `--output PATH` | Write formatted output to a file (check itself does not touch the tree) |

**Exit codes:** `0` — no violations; `1` — rule violations; `2` — fail-closed
(config, git, parse, version mismatch); `3` — internal JAILint bug.

Julia API: `JAILint.check(root; ...) -> CheckResult`. The CLI is a thin adapter.

## Architecture (six layers)

```text
┌─────────────────────────────────────────────────────────────┐
│ 1. Entry (JAILint.jl)     @main CLI → exit 0/1/2/3          │
├─────────────────────────────────────────────────────────────┤
│ 2. Types & Config         PolicyBundle, typed errors, pins  │
├─────────────────────────────────────────────────────────────┤
│ 3. Syntax Adapter & Diff  JuliaSyntax 2.0, expect anchors,  │
│                           constant folder, git diff         │
├─────────────────────────────────────────────────────────────┤
│ 4. Rules                  [JAILint] + [Preset] + [Project]  │
├─────────────────────────────────────────────────────────────┤
│ 5. Runner                 Discover files, ceilings, expects │
├─────────────────────────────────────────────────────────────┤
│ 6. Formatters             human / agent / json / report     │
└─────────────────────────────────────────────────────────────┘
```

**Rule origins**

| Label | Source |
| --- | --- |
| `[JAILint]` | Built-in standards (`protected-paths`, `expect-audit`, …) |
| `[Preset]` | Opt-in tables (e.g. `shell-safety/process-pattern`) |
| `[Project]` | `[[project_rules]]` in `.JAILintConfig.toml` (`project/<id>`) |

**Syntax adapter:** `JuliaSyntax` API churn stays under `src/syntax/`.
`# jailint-expect:` lines are detected via the tokenizer as standalone comment
lines, then matched to per-rule anchor lines (not green-tree trivia).
**Constant folding** (`*`, `string`, `join`, …) is shared by preset and project
rules.

**Parse, don't validate:** policy is loaded once into immutable structs; rules are
pure over `FileContext` and do not perform their own git I/O.

## 0.1.0-DEV rule map (summary)

**Implemented in this dev tree:** `expect-audit` and `[[project_rules]]` (`project/<id>`).
Other built-in rows are **roadmap** (planned for 0.1.0 / 0.2.0), not active yet.

| Rule ID | Status | Level | Layer |
| --- | --- | --- | --- |
| protected-paths | planned | forbid | Diff + config semantics |
| scope-paths | planned | forbid | Trusted `--allow-paths` enforcement |
| ceiling-ratchet | planned | forbid | `.jailint/ceilings.toml` monotonic caps |
| expect-audit | **implemented** | forbid | `# jailint-expect:` line anchors |
| manifest-sync | planned | deny | Tracked Manifest vs Project |
| shell-safety/process-pattern | planned | deny | Preset: shell / `Cmd` hazards |
| silent-catch | planned | deny | Swallowed exceptions |
| test-integrity | planned | deny | Weakened or hollow tests |
| unsafe-boundary | planned | warn | `eval`, `ccall`, `unsafe_*`, … |
| project/(config `id`) | **implemented** | (config) | Declarative `forbid_literals` |

Run `jailint explain <id>` for anchor and expect details. Runic **invariance**
is tested: formatting must not change diagnostic signatures on the golden
corpus under `test/corpus/`.

## Output formats

- **`human`:** `StyledStrings` tree (`┌` / `│` / `└`), origins `[JAILint]` /
  `[Project]`, `intent` / `do_not`, snippet under each hit.
- **`agent`:** No ANSI; one `intent`/`do_not` block per rule; hits as
  `path:line:col-line:col | message`; `... (+N omitted)` past `max_hits_per_rule`.
- **`json`:** JSONL records: `header` (versions, `config_source`,
  `position_encoding`), `diagnostic` rows (including suppressed), `summary`
  with `complete: true`.

Schema stability is keyed on `jailint_version` in the header; other string fields
may evolve toward SARIF in later releases.

## Configuration

Root file: **`.JAILintConfig.toml`** with `jailint_version = "=0.1.0"` pin matching
the package minor. Ceilings: **`.jailint/ceilings.toml`** (only monotonic
decreases are exempt from protected-path rules when reviewed).

Level 1 custom rules: `[[project_rules]]` with `paths`, `forbid_literals`,
`intent`, and `do_not`. Level 2 executable `.jailint/rules/*.jl` is **out of
scope** for 0.1.0 (process isolation deferred).

## Ecosystem boundary (non-interference)

| Tool | Owns | JAILint behavior |
| --- | --- | --- |
| **Runic** | Formatting, whitespace | No format rules; expects on standalone lines; Runic invariance tested |
| **JETLS** | Types, undefined refs, inference tests | Run alongside; protect `.JETLSConfig.toml`; `test-integrity` avoids “always failing” tests |
| **Aqua** | Ambiguities, deps hygiene, piracy | Delegate package health; JAILint self-tests with Aqua |
| **ExplicitImports** | Import hygiene | No duplicate import rules |
| **CodeRabbit** | Semantic PR review | No auto PR comments; deterministic rules only; JSON/SARIF friendly |
| **JAILint** | Invariants, intent, boundaries | Fills gaps: protected files, manifests, expects, project literals |

## Trust model (short)

On `pull_request`, workflow YAML comes from the PR branch—so **repository
rulesets**, required checks, and CODEOWNERS on protected paths provide the
hard guarantee. JAILint supplies early feedback and (in consumer repos) composite
action runs with a pinned `env` project. Local `--config-from` is advisory
pre-push signal, not a substitute for CI base policy.

## Contributing and security

- **Issues:** use GitHub issue forms ([false positive](.github/ISSUE_TEMPLATE/false-positive.yml), [evasion proposal](.github/ISSUE_TEMPLATE/evasion-rule-proposal.yml), [bug](.github/ISSUE_TEMPLATE/bug-report.yml)). See [CONTRIBUTING.md](CONTRIBUTING.md).
- **Vulnerabilities** (e.g. bypassing `protected-paths` or `--config-from`): see [SECURITY.md](SECURITY.md) — use private reporting, not public issues.

## License

MIT — see [LICENSE](LICENSE).
