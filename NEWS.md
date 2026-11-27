# AgentRuleLint.jl NEWS

CI-breaking changes are marked **[CI-breaking]**. Tracked from [#65](https://github.com/yamanori99/AgentRuleLint.jl/issues/65).

## Unreleased (0.1.0-DEV)

### `exit_severity` and `--exit-severity`

`check` can raise the fail threshold to `deny` or `forbid` via config
`exit_severity` or `--exit-severity`. The default remains **`warn`** (same
exit as today). `forbid` findings always fail. A CLI override is printed on
the verdict line. JSON summaries add `threshold` and `threshold_source`.

### **[CI-breaking]** `on_allow_rule = "error"` is a ConfigError

`on_allow_rule` now accepts only the rule-level vocabulary `forbid|deny|warn|allow`.
The former sentinel `"error"` is rejected with exit code 2 (`ConfigError`).

Migrate by choosing an explicit level, for example:

```toml
[rules.expect-audit]
on_allow_rule = "forbid"
```

### **[CI-breaking]** Fold-budget exhaustion is `analysis-incomplete` (not exit 3)

Constant-fold step-budget exhaustion (`FoldBudgetExceeded`) emits the built-in
integrity rule `analysis-incomplete` (`:forbid`, never expect-suppressible) with
message `analysis incomplete: constant-fold budget exceeded in <file> (<analyzer>)`.
Project-rule literal folding, shell-safety Cmd folding, and test-integrity `@test`
folding share this rule (at most one finding per file). It no longer maps to an
internal-error exit code.

Migrate notes:

- Project rules that previously truncated folding silently now fail CI with a
  `forbid` finding when the budget is exhausted.
- test-integrity's former `deny` "too complex to verify" finding could be
  suppressed with a reasoned expect; `analysis-incomplete` cannot.

### InternalError retains backtrace

Unexpected errors wrapped by `check` keep a concrete `stacktrace(catch_backtrace())`
on `InternalError`; the CLI prints that backtrace (Phase 3 /
[#66](https://github.com/yamanori99/AgentRuleLint.jl/issues/66) / [#28](https://github.com/yamanori99/AgentRuleLint.jl/issues/28)).

### Changed

#### `silent-catch` default level is `warn` (was `deny`)

With no `.AgentRuleLintConfig.toml`, `silent-catch` now defaults to **`warn`**.
Restore the previous built-in default with explicit config:

```toml
[rules.silent-catch]
level = "deny"
```

This repository’s dogfood config keeps `level = "deny"`.

#### `@inbounds`, `@generated`, `@assume_effects` are opt-in (`unsafe-boundary/strict`)

Core **`unsafe-boundary`** keeps `eval`/`@eval`, `Meta.parse`, `ccall`/`@ccall`,
`invokelatest`, `unsafe_*`, and alias/escape tracking. Strict macro checks moved to
preset **`unsafe-boundary/strict`** (same mechanism as `shell-safety`):

```toml
presets = ["unsafe-boundary/strict"]

[rules."unsafe-boundary/strict"]
level = "warn"
```

Restore pre-0.1.0 macro coverage by enabling that preset (and optionally lowering
or raising `level`). This repo enables the preset via dogfood config (protected
path; see PR description).

#### `explain` works for built-in rules that are not enabled

`agentrulelint explain <id>` resolves every built-in / preset id from `RULE_DEFS_BY_ID`,
even when the current config does not enable that rule ([#82](https://github.com/yamanori99/AgentRuleLint.jl/issues/82)).
Inactive built-ins include `status: not enabled in this config` and print
`level: <level> (default when enabled)` so the level is not read as active policy.
`unknown rule id: <id>` (exit 2) is reserved for ids that exist nowhere (not built in,
not declared under `project_rules`). Known preset names (e.g. `shell-safety`) stay
unknown but append a `did you mean <rule-id>?` hint.

`check` is unchanged.

Migrate notes:

- Scripts or goldens that expected exit 2 for `explain shell-safety/process-pattern`,
  `explain test-integrity`, or `explain unsafe-boundary` under a config that does not
  enable them must expect exit 0 and the new `status:` / default-level lines instead.

#### Built-in `intent` / `do_not` when config omits them

Rules whose config omits `intent`/`do_not` now show the built-in text in `explain`,
human, and agent output (previously empty).

#### Deterministic `agent` and piped `human` line layout

`agent` output no longer word-wraps to terminal width or `ENV["COLUMNS"]`; each
field stays on one line and long text is truncated at a fixed cap. Piped or
redirected `human` output likewise does not wrap (`COLUMNS` is ignored). Interactive
TTY `human` still wraps at the terminal width (capped at 80). Exit codes and
violation counts are unchanged.
