@testset "exception to exit code table" begin
    cases = [
        (AgentRuleLint.InternalError("boom"), 3),
        (AgentRuleLint.ConfigError("bad config"), 2),
        (AgentRuleLint.GitError("bad git"), 2),
        (AgentRuleLint.ParseError("bad parse"), 2),
        (ArgumentError("bad arg"), 2),
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

@testset "InternalError keeps backtrace" begin
    bt = stacktrace()
    err = AgentRuleLint.InternalError("wrapped: root cause", bt)
    @test err.bt === bt
    @test !isempty(err.bt)
    buf = IOBuffer()
    code = AgentRuleLint._emit_fail_closed(err, buf)
    @test code == 3
    text = String(take!(buf))
    @test occursin("AgentRuleLint internal error: wrapped: root cause", text)
    @test occursin("root cause", sprint(showerror, err))
end
