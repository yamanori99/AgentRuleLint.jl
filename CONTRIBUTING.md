# Contributing to AgentRuleLint.jl

Thank you for helping improve AgentRuleLint—whether you are a human maintainer or an
agent filing structured feedback. This project favors **constructive** reports
that become golden corpus tests, not drive-by complaints.

## Ways to contribute

| Channel | Use when |
| --- | --- |
| [False positive](.github/ISSUE_TEMPLATE/false-positive.yml) | A rule fires on correct, idiomatic Julia |
| [Evasion / rule proposal](.github/ISSUE_TEMPLATE/evasion-rule-proposal.yml) | A pattern should be caught or explicitly allowed; no overlap with JETLS/Runic/Aqua/ExplicitImports |
| [Bug report](.github/ISSUE_TEMPLATE/bug-report.yml) | Crashes, exit `2`/`3`, or fail-closed surprises |
| [Private security advisory](SECURITY.md) | Exploits against `protected-paths`, `--config-from`, or trust boundaries |
| Pull request | Code, corpus fixtures, docs (open an issue first for large rule changes) |

## Reporting workflow for humans and agents

### 1. Reproduce locally

From the repository root, with the same Julia version as CI (1.13+):

```bash
julia --startup-file=no --project=. -m AgentRuleLint check --format=json PATH > /tmp/agentrulelint.jsonl
```

Or for agent-friendly output:

```bash
julia --startup-file=no --project=. -m AgentRuleLint check --format=agent PATH
```

### 2. Capture a `agentrulelint report` bundle (recommended)

When you have a diagnostic **fingerprint** from JSON or agent output:

```bash
julia --startup-file=no --project=. -m AgentRuleLint report 'v1:YOUR_FINGERPRINT'
```

Paste the emitted JSON lines into the issue form’s **JSON header** field and
attach the anonymized snippet block. This keeps reports concise and avoids
leaking repository-specific identifiers.

### 3. File via GitHub issue forms

Issue forms require:

- **Rule ID** (dropdown) or project rule id
- At least one **JSON header** line (`{"type":"header",...}`)
- A **minimal Julia snippet** (length-limited; prefer `report` output)
- **No secrets** confirmation
- **MIT corpus consent** if you agree we may commit your snippet to
  `test/corpus/` (anonymized)

If the report was **AI-assisted**, say so and name the model (helps us tune
`--format=agent`).

### 4. What maintainers do with reports

| Issue type | Typical landing zone |
| --- | --- |
| False positive | `test/corpus/` regression fixture |
| Evasion proposal | `test/corpus/` + rule or preset design |
| Bug | Unit test at the fail-closed boundary or syntax adapter |

Triage automation may label and comment on missing fields; issues are **not**
auto-closed for incomplete reports.

## Rule admission and design policy

### Integrity vs explicitness

- **Integrity guards** (`protected-paths`, `scope-paths`, `ceiling-ratchet`, `expect-audit`,
  `manifest-sync`, `test-integrity`): near-zero false-positive bar; fail closed on policy,
  manifests, protected paths, expect hygiene, and test integrity.
- **Explicitness / boundary contracts** (`silent-catch`, `unsafe-boundary`, opt-in presets): judged by
  noise budget on the reference corpus plus either a clean fix or a reason-bearing
  `# agentrulelint-expect:` / `# SAFETY:` annotation.

### Groups × profiles

Rules carry a **group** (`integrity`, `correctness`, `explicitness`, `boundary`,
`nursery`) and a **profile** (`adopt`, `standard`, `agent`). New rules require
`intent`, `do_not`, `fix` guidance, an anchor definition, golden plus adversarial
evasion corpus entries, and a **Runic invariance** test. Retired rule slug IDs are never
reused.

### Non-goals (NG1–NG5)

1. **NG1:** No mandates for exhaustive type annotations or rigid hierarchies that break
   idiomatic generic Julia.
2. **NG2:** Do not replace Julia’s exception model with `Result`-style wrappers; target
   silent swallowing, not exceptions themselves.
3. **NG3:** Do not ban idiomatic top-level metaprogramming or macro DSLs; target
   runtime evaluation and boundary escapes.
4. **NG4:** Do not duplicate JETLS, JET, Aqua, Runic, ExplicitImports, ReLint/Argus,
   Fatou, or test-framework duties.
5. **NG5:** Reject rules that are easier to satisfy via cosmetic syntax evasion than
   via a real fix (validate against an adversarial evasion corpus before adoption).

## Golden corpus

`manifest-sync` skips git-tracked manifests under `test/corpus/manifest_sync/` when linting this repository (intentional negative fixtures); manifests elsewhere in the tree are still checked.

Under `test/corpus/`:

- **Existing fixtures** exercise constant folding, UTF-8, and expect anchors.
- New issues may add files under `test/corpus/` after review.
- Every corpus `.jl` file participates in **Runic invariance**: diagnostics must
  match before and after `Runic.format_str` (see `test/test_runic_invariance.jl`).

When proposing corpus entries, strip secrets, tokens, and customer paths. Prefer
`agentrulelint report` anonymization.

## Development setup

```bash
git clone https://github.com/yamanori99/AgentRuleLint.jl.git
cd AgentRuleLint.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using Pkg; Pkg.test()'
```

From the repository root (after `Pkg.instantiate()`):

```bash
julia --startup-file=no --project=. -m AgentRuleLint check
julia --startup-file=no --project=. -m AgentRuleLint check src --format=agent
julia --startup-file=no --project=. -m AgentRuleLint explain expect-audit
```

Runic checks use an isolated env at `test/runic_env/` (CI and local tests).

## Code guidelines

- Match existing style in `src/`; run Runic on edited Julia files when practical.
- Rules stay pure: no hidden I/O inside rule functions.
- Document new rules with `intent` and `do_not` in config samples and `explain`.
- Do not add rules that duplicate JETLS, Aqua, ExplicitImports, or Runic.

## Pull requests

- Keep changes focused; one lever per PR when hill-climbing rule behavior.
- Include or update corpus tests for behavior changes.
- Ensure CI passes (Julia 1.13 tests, Aqua, Runic invariance).

## Code of conduct

Be direct and kind. Disagree on rules with data (reproductions), not tone.
Agents filing issues must follow the same no-secrets and corpus-consent checkboxes
as humans.
