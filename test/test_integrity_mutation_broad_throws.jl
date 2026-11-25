using AgentRuleLint

res = AgentRuleLint.check(
    ".";
    paths = [joinpath("test", "corpus", "test_integrity_broad_throws.jl")],
)
ok = any(d -> d.rule_id == "test-integrity" && !d.suppressed, res.violations)
exit(ok ? 0 : 2)
