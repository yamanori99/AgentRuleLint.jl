# JSON output (`--format=json`)

AgentRuleLint writes **JSONL**: one JSON object per line, always in this order:

1. `header`
2. `diagnostic` (zero or more, sorted by `path`, `span`, `rule_id`, `fingerprint`)
3. `summary`

## Unstable fields in 0.1.0

Consumers should tolerate unknown keys. These fields may change wording or structure before 1.0:

| Record | Field | Note |
| --- | --- | --- |
| header | `parser` | JuliaSyntax revision string |
| diagnostic | `message` | Human-readable text may be refined |

Stable identifiers for automation: `rule_id`, `fingerprint`, `span`, `expect_status`, `suppressed`, and summary counts.

Validate output against `schemas/check-jsonl.schema.json` (array-of-lines shape for batch validators).