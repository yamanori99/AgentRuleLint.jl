# Contributing to JAILint.jl

Thank you for helping improve JAILint—whether you are a human maintainer or an
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
julia --startup-file=no --project=. -m JAILint check --format=json PATH > /tmp/jailint.jsonl
```

Or for agent-friendly output:

```bash
julia --startup-file=no --project=. -m JAILint check --format=agent PATH
```

### 2. Capture a `jailint report` bundle (recommended)

When you have a diagnostic **fingerprint** from JSON or agent output:

```bash
julia --startup-file=no --project=. -m JAILint report 'v1:YOUR_FINGERPRINT'
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
| False positive | `test/corpus/false_positives/` regression |
| Evasion proposal | `test/corpus/evasions/` + rule or preset design |
| Bug | Unit test at the fail-closed boundary or syntax adapter |

Triage automation may label and comment on missing fields; issues are **not**
auto-closed for incomplete reports.

## Golden corpus

Under `test/corpus/`:

- **Existing fixtures** exercise constant folding, UTF-8, and expect anchors.
- New issues may add files under `false_positives/` or `evasions/` after review.
- Every corpus `.jl` file participates in **Runic invariance**: diagnostics must
  match before and after `Runic.format_str` (see `test/test_runic_invariance.jl`).

When proposing corpus entries, strip secrets, tokens, and customer paths. Prefer
`jailint report` anonymization.

## Development setup

```bash
git clone https://github.com/yamanori99/JAILint.jl.git
cd JAILint.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using Pkg; Pkg.test()'
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
