# AgentRuleLint.jl NEWS

CI-breaking changes are marked **[CI-breaking]**. Tracked from [#65](https://github.com/yamanori99/AgentRuleLint.jl/issues/65).

## Unreleased (0.1.0-DEV)

### **[CI-breaking]** `explain` works for built-in rules that are not enabled

`agentrulelint explain <id>` resolves every built-in / preset id from `RULE_DEFS_BY_ID`,
even when the current config does not enable that rule ([#82](https://github.com/yamanori99/AgentRuleLint.jl/issues/82)).
Inactive built-ins include `status: not enabled in this config` so the text is not
mistaken for active policy. `unknown rule id: <id>` (exit 2) is reserved for ids that
exist nowhere (not built in, not declared under `project_rules`).

`check` is unchanged.

Migrate notes:

- Scripts or goldens that expected exit 2 for `explain shell-safety/process-pattern`,
  `explain test-integrity`, or `explain unsafe-boundary` under a config that does not
  enable them must expect exit 0 and the new `status:` line instead.
