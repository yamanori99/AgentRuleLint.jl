# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x (0.1.0-DEV) | Yes |

## Reporting a vulnerability

**Do not** open a public GitHub issue for security problems.

Use [GitHub Private Vulnerability Reporting](https://github.com/yamanori99/AgentRuleLint.jl/security/advisories/new)
for this repository, or email the maintainer listed in `Project.toml` if
reporting is unavailable.

We aim to acknowledge reports within a reasonable window and coordinate a fix
before public disclosure.

## What belongs in a private report

Report **exploitable** weaknesses in AgentRuleLint’s trust model, including but not
limited to:

- Bypassing **`protected-paths`** so agents can silently weaken
  `.AgentRuleLintConfig.toml`, `.JETLSConfig.toml`, workflow files, `Manifest*.toml`,
  or other designated protected paths without failing the check.
- Abusing **`--config-from`** or git merge/diff handling to make CI compare against
  attacker-controlled policy while appearing to use base policy.
- Circumventing **`# agentrulelint-expect:` (`expect-audit`)** or **ceiling ratchet (`ceiling-ratchet`)** in
  ways that hide violations in CI.
- Composite action / pinned-environment bypass that runs unreviewed code with
  repository write implications.
- Information disclosure via diagnostic output when that crosses a documented
  trust boundary (not routine linter snippets).

## What is out of scope for private reporting

- Ordinary **false positives** or missing rules (use issue forms instead).
- Feature requests and ecosystem overlap debates.
- Issues in **downstream consumer workflows** unless the root flaw is in
  AgentRuleLint itself.
- Social engineering or stolen credentials (report to the platform).

## Safe disclosure expectations

Please include:

1. AgentRuleLint version (`AgentRuleLint.AGENTRULELINT_VERSION` or package version).
2. Julia version.
3. Minimal reproduction steps (config + file diff or command line).
4. Impact: what an agent or PR could do that maintainers intended to block.

Avoid attaching live tokens, production URLs with secrets, or customer data.

## After a fix

We will add a **non-identifying regression test** where possible (often derived
from advisory details after consent). Public credit is given if you wish.

## Ecosystem note

AgentRuleLint is one layer in a stack (Rulesets, CODEOWNERS, JETLS, Aqua, Runic).
A complete deployment review may require hardening those controls as well; we are
happy to document recommended pairings without blaming users for misconfiguration.
