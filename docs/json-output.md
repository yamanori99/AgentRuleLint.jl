# CLI output formats

## JSON (`--format=json`)

AgentRuleLint writes **JSONL**: one JSON object per line, always in this order:

1. `header`
2. `diagnostic` (zero or more, sorted by `path`, `span`, `rule_id`, `fingerprint`)
3. `summary`

`format_json` (`src/format/json.jl`) header keys: `type` (`"header"`),
`version`, `julia_version`, `parser`, `config_source`, `position_encoding`
(`"utf8-codepoint-1based"`). `parser` is `JuliaSyntax@<major>.<minor>` from
`VERSION` (#76), not a JuliaSyntax git rev.

### Unstable fields in 0.1.0

Consumers should tolerate unknown keys. Schemas become the versioned contract
in #111 (planned).

`message` wording may change before 1.0. Stable for automation: `rule_id`,
`fingerprint`, `span`, `expect_status`, `suppressed`, and summary counts.

Validate output against `schemas/check-jsonl.schema.json` (array-of-lines shape for batch validators).

## Human and agent (`ceiling`)

**Human** rule headers print `ceiling N` via `human_ceiling_display` (numeric,
including **`ceiling 0`** when the stored sum is zero). **Agent** prints
`ceiling=N` when that sum is `> 0`, otherwise **`ceiling=-`**.

Ceiling **enforcement** (`ceiling-ratchet`) runs in `run_check` / `_run_check_pipeline`
when a working-tree (and, with `--diff`, base) ceilings file is in play.

## `agentrulelint explain`

`explain <rule-id>` resolves built-in ids from `RULE_DEFS_BY_ID` even when the
current config does not enable them (#83); inactive built-ins print
`status: not enabled in this config` and `level: … (default when enabled)`.
Project ids use `project/<slug>` from `[[project_rules]]`.

**Unknown ids exit 2.** Known preset *names* that are not rule ids get a
`did you mean` hint. Levels shown are policy values when the rule is enabled,
otherwise the `RuleDef` default.

Explain extra blocks (anchor, config, detail) live on the `RuleDef` extras,
attached at explain time.
