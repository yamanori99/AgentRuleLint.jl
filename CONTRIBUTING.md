# Contributing to AgentRuleLint.jl

Thank you for helping improve AgentRuleLint. This project favors constructive
reports that become golden corpus tests, not drive-by complaints.

## Ways to contribute

- [False positive](.github/ISSUE_TEMPLATE/false-positive.yml): a rule fires on correct, idiomatic Julia.
- [Evasion / rule proposal](.github/ISSUE_TEMPLATE/evasion-rule-proposal.yml): a pattern should be caught or explicitly allowed; no overlap with JETLS, Runic, Aqua, or ExplicitImports.
- [Bug report](.github/ISSUE_TEMPLATE/bug-report.yml): crashes, exit 2/3, or fail-closed surprises.
- [Private security advisory](SECURITY.md): exploits against trust boundaries.
- Pull request: code, corpus fixtures, docs. Open an issue first for rule changes.

## Reporting

From the repository root (Julia 1.13+): `agentrulelint check --format=agent PATH`
or `--format=json`, then `agentrulelint report <fingerprint>`.

Issue forms need the rule ID, the report output, a minimal snippet, a no-secrets
confirmation, and corpus consent if we may commit an anonymized fixture to
`test/corpus/`. Say if the report was AI-assisted.

## Non-goals (NG1–NG5)

This list is the single source for non-goals.

1. **NG1:** No mandates for exhaustive type annotations or rigid hierarchies that break idiomatic generic Julia.
2. **NG2:** Do not replace Julia’s exception model with `Result`-style wrappers; target silent swallowing, not exceptions themselves.
3. **NG3:** Do not ban idiomatic top-level metaprogramming or macro DSLs; target runtime evaluation and boundary escapes.
4. **NG4:** Do not duplicate JETLS, JET, Aqua, Runic, ExplicitImports, ReLint/Argus, Fatou, or test-framework duties.
5. **NG5:** Reject rules that are easier to satisfy via cosmetic syntax evasion than via a real fix (validate against an adversarial evasion corpus before adoption).

Integrity rules have a near-zero false-positive bar and cannot be weakened by
config. For which rules that applies to, run `agentrulelint explain <rule-id>`.

Built-in rules ship with the package; presets are opt-in sets enabled with
`presets = [...]`; project rules are declared under `[[project_rules]]` with
IDs `project/<slug>`. A new rule starts as a project rule or a preset and becomes
built-in only if it meets the near-zero false-positive bar and does not duplicate
JETLS, JET, Aqua, Runic, or ExplicitImports (NG4).

## Golden corpus

Strip secrets, tokens, and customer paths. Prefer `agentrulelint report`
anonymization. Every `.jl` corpus file is subject to Runic invariance.

## Development

```bash
git clone https://github.com/yamanori99/AgentRuleLint.jl.git
cd AgentRuleLint.jl
julia +1.13 --project=. -e 'using Pkg; Pkg.instantiate()'
```

Then follow [`.agents/skills/pre-push-gate/SKILL.md`](.agents/skills/pre-push-gate/SKILL.md)
(tests, digest, mutation, JETLS). A new or changed detector ships with a corpus
case and a mutation file under `test/mutation/`.

## Pull requests

One change per PR. CI green.

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
