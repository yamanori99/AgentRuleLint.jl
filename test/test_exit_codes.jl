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

@testset "fold budget exhaustion is a diagnostic" begin
    src = "a = \"x\" * \"y\"\nb = \"p\" * \"q\"\nc = \"r\" * \"s\"\n"
    tree = AgentRuleLint.parse_source(src)
    partial = AgentRuleLint.collect_folded_string_exprs(tree, src; max_steps = 15)
    @test !isempty(partial.folds)
    @test partial.budget_exceeded
    cmd_src = "Cmd([$(join(fill("\"a\"", 200), ", "))])\n"
    cmd_tree = AgentRuleLint.parse_source(cmd_src)
    cmd_partial = AgentRuleLint.collect_cmd_string_literals(cmd_tree, cmd_src; max_steps = 15)
    @test cmd_partial.budget_exceeded
    @test AgentRuleLint._fold_budget_exceeded(AgentRuleLint.FoldBudgetExceeded(15))
    @test !AgentRuleLint._fold_budget_exceeded(ArgumentError("constant fold step budget exceeded"))
end

@testset "fold budget incomplete is not expect-suppressible" begin
    source = "x = 1\n"
    d = AgentRuleLint.Violation(
        "project/no-pad",
        :project,
        :forbid,
        "f.jl",
        AgentRuleLint.Span(1, 1, 1, 1),
        1,
        "",
        :none,
        false,
        AgentRuleLint.fold_budget_incomplete_message("f.jl"),
        "i",
        "d",
    )
    diags = [d]
    expects = [AgentRuleLint.ExpectLine(1, "project/no-pad", "excuse long enough", "raw")]
    AgentRuleLint.apply_expect_suppression!(diags, expects, source)
    @test !diags[1].suppressed
    @test AgentRuleLint.is_fold_budget_incomplete(diags[1])
end

@testset "project-rule fold budget emits analysis incomplete" begin
    root = mktempdir()
    try
        v = string(pkgversion(AgentRuleLint))
        write(
            joinpath(root, ".AgentRuleLintConfig.toml"),
            """
            agentrulelint_version = \"=$(v)\"
            [rules.expect-audit]
            level = \"forbid\"
            on_allow_rule = \"warn\"
            [[project_rules]]
            id = \"no-pad\"
            level = \"deny\"
            paths = [\"**/*.jl\"]
            forbid_literals = [\"SECRET_PAD\"]
            intent = \"t\"
            do_not = \"d\"
            """,
        )
        pad = join(fill("\"a\"", 5000), " * ")
        write(joinpath(root, "padded.jl"), "x = $pad\ny = \"SECRET_PAD\"\n")
        res = AgentRuleLint.check(root; paths = ["padded.jl"])
        incomplete = filter(AgentRuleLint.is_fold_budget_incomplete, res.violations)
        @test !isempty(incomplete)
        @test all(d -> d.level == :forbid && !d.suppressed, incomplete)
        @test res.exit_code != 3
    finally
        rm(root, recursive = true, force = true)
    end
end

@testset "InternalError keeps cause and backtrace" begin
    cause = ErrorException("root cause")
    bt = Base.backtrace()
    err = AgentRuleLint.InternalError("wrapped", cause, bt)
    @test err.cause === cause
    @test err.bt === bt
    buf = IOBuffer()
    code = AgentRuleLint._emit_fail_closed(err, buf)
    @test code == 3
    text = String(take!(buf))
    @test occursin("AgentRuleLint internal error: wrapped", text)
    @test occursin("root cause", sprint(showerror, err))
end
