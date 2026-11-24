# CLI output formats

## JSON (`--format=json`)

AgentRuleLint writes **JSONL**: one JSON object per line, always in this order:

1. `header`
2. `diagnostic` (zero or more, sorted by `path`, `span`, `rule_id`, `fingerprint`)
3. `summary`

The header record uses the field name **`version`** (package version string), not a separate legacy key.

### Unstable fields in 0.1.0

Consumers should tolerate unknown keys. These fields may change wording or structure before 1.0:

| Record | Field | Note |
| --- | --- | --- |
| header | `parser` | JuliaSyntax revision string |
| diagnostic | `message` | Human-readable text may be refined |

Stable identifiers for automation: `rule_id`, `fingerprint`, `span`, `expect_status`, `suppressed`, and summary counts.

Validate output against `schemas/check-jsonl.schema.json` (array-of-lines shape for batch validators).

## Human and agent (`ceiling=`)

Both **human** and **agent** rule headers include `count=` (active hits for that rule in the current run) and `ceiling=` (sum of per-path violation counts stored under `[violations."<rule_id>"]` in `.agentrulelint/ceilings.toml`).

When the ceilings file is missing, empty for that rule, or sums to zero, formatters print **`ceiling=-`**. That does not imply a numeric limit of zero; it means no stored ratchet baseline is available. Ceiling **enforcement** (`ceiling-ratchet`) is not wired in `run_check` on this branch.

## `agentrulelint explain`

`explain <rule-id>` prints text only for rules that exist in the loaded policy or built-in registry after `init_registry!`:

- Tables under `[[rules]]` / `[rules.*]` in `.AgentRuleLintConfig.toml`
- Built-ins registered from policy (including the default `expect-audit` fallback when omitted from config)
- `project/<slug>` ids from `[[project_rules]]`

**Unknown ids exit 2.** Rules that are planned but not registered on this branch (for example `silent-catch`) are not listed and cannot be explained until their rule PR adds registry entries and config.

Levels shown are the effective values from policy (`RuleSpec.level` or `ProjectRule.level`), not hard-coded severities.

Explain anchor/example lines for built-ins live on the rule definition (`RuleSpec.extra`, filled at registration time for rules that define them, such as `expect-audit`).
