@testset "exception to exit code table" begin
    cases = [
        (AgentRuleLint.InternalError("boom"), 3),
        (AgentRuleLint.ConfigError("bad config"), 2),
        (AgentRuleLint.GitError("bad git"), 2),
        (AgentRuleLint.ParseError("bad parse"), 2),
        (ArgumentError("bad arg"), 2),
        (AgentRuleLint.FoldBudgetExceeded(16), 3),
        (ErrorException("unexpected"), 3),
    ]
    for (err, want) in cases
        @test AgentRuleLint.exit_code_for_error(err) == want
    end
end

@testset "on_allow_rule uses rule-level vocabulary" begin
    root = mktempdir()
    try
        write(
            joinpath(root, ".AgentRuleLintConfig.toml"),
            """
            agentrulelint_version = \"=$(AgentRuleLint.AGENTRULELINT_VERSION)\"
            [rules.expect-audit]
            level = \"forbid\"
            on_allow_rule = \"forbid\"
            """,
        )
        pol = AgentRuleLint.resolve_policy(root)
        @test pol.on_allow_rule == :forbid
        write(
            joinpath(root, ".AgentRuleLintConfig.toml"),
            """
            agentrulelint_version = \"=$(AgentRuleLint.AGENTRULELINT_VERSION)\"
            [rules.expect-audit]
            level = \"forbid\"
            on_allow_rule = \"error\"
            """,
        )
        @test_throws AgentRuleLint.ConfigError AgentRuleLint.resolve_policy(root)
    finally
        rm(root, recursive = true, force = true)
    end
end

@testset "fold budget uses FoldBudgetExceeded" begin
    src = "a = \"x\" * \"y\"\nb = \"p\" * \"q\"\nc = \"r\" * \"s\"\n"
    tree = AgentRuleLint.parse_source(src)
    partial = AgentRuleLint.collect_folded_string_exprs(tree, src; max_steps = 15)
    @test !isempty(partial)
    @test AgentRuleLint._fold_budget_exceeded(AgentRuleLint.FoldBudgetExceeded(15))
    @test !AgentRuleLint._fold_budget_exceeded(ArgumentError(AgentRuleLint.FOLD_BUDGET_MSG))
end
