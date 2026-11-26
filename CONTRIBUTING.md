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
- At least one **JSON header** line (`{"type":"header","version",...}`)
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
- **`protected-paths`, `scope-paths`, and `ceiling-ratchet`** must be declared with
  `level = "forbid"` in `.AgentRuleLintConfig.toml`. Any other level is a **ConfigError** (exit 2)
  so agents cannot weaken enforcement by editing policy in the same diff.
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

`manifest-sync` golden fixtures under `test/corpus/manifest_sync/` are stored as `*.toml.fixture` (not tracked as `Project.toml` / `Manifest*.toml`); tests materialize them in a temp git repo.

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
julia +1.13 --project=. -e 'using Pkg; Pkg.instantiate()'
julia +1.13 --startup-file=no --project=. -e 'using Pkg; Pkg.test()' 2>&1 | tee /tmp/agentrulelint-test.log
```

Always capture `Pkg.test()` with `tee` as above. Failures print mid-run; the
end of the log has a block starting with
`=== AgentRuleLint test failure digest ===` (testset path, `file:line`, first
line of the message; `no failures` when clean). The same text is written to
`test/last_failures.txt` (gitignored, overwritten every run).

On failure, read that digest (`tail` of the log or `test/last_failures.txt`) or
`grep -n "Test Failed\|Error During Test" /tmp/agentrulelint-test.log`. Do **not**
re-run the full suite only to see which tests failed. Re-run the affected group
(via test selection once it exists), then run the full suite **once** before
pushing.

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

## Mutation harnesses

Standalone detector mutations live under `test/mutation/` (one script per case,
plus `mutation_lib.jl`). They patch a **temp copy** of the repo only—never real
`src/`. Run them locally with Julia 1.13:

```bash
julia +1.13 --startup-file=no --project=. test/mutation/run_all.jl
```

`run_all.jl` discovers every `test/mutation/*.jl` except `mutation_lib.jl` /
itself (glob, not a hand list). CI runs the same entry point in the
**Mutation (Julia 1.13, ubuntu-latest, x64)** job on every `pull_request` and
`push` to `main`.

A new or changed detector should ship with a mutation file in that directory.
After the job exists, a repository owner must add that job name to branch
protection as a **required** check (agents do not change repo settings).

## Pull requests

- Keep changes focused; one lever per PR when hill-climbing rule behavior.
- Include or update corpus tests for behavior changes.
- Ensure CI passes (Julia 1.13 tests, Aqua, Runic invariance, Mutation).

### Interim: merging changes that trip `protected-paths`

Until [#70](https://github.com/yamanori99/AgentRuleLint.jl/issues/70) lands an
approval path agents cannot forge, every PR that edits protected paths (including
`.AgentRuleLintConfig.toml`, and the broader set #70 will add) fails
`protected-paths` by design. Merging red PRs without a written rule would
normalize ignoring the check. Use this procedure instead (tracked in
[#71](https://github.com/yamanori99/AgentRuleLint.jl/issues/71)):

1. **Split PRs.** Code changes (for example fixture exclusion) go in their own
   PR and must be green. Config, workflow, and other protected-path changes go
   in a separate PR.
2. **Only `protected-paths` may be red.** Every other check on that PR must be
   green.
3. **Exact match.** The PR description lists the protected files it changes
   under **Protected paths changed**. The `protected-paths` violations must
   match that list exactly.
4. **Owner merges manually** after checking (2) and (3). Agents never merge or
   approve these PRs.
5. **Dogfood job stays non-required** until the approval path in #70 lands.
   Making it required earlier would block all legitimate config changes.

When #70's approval path lands, remove this subsection and make the dogfood job
required.

## Code of conduct

Be direct and kind. Disagree on rules with data (reproductions), not tone.
Agents filing issues must follow the same no-secrets and corpus-consent checkboxes
as humans.
