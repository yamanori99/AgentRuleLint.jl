@testset "analysis-incomplete rule" begin
    @testset "fold budget collectors report budget_exceeded" begin
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
    end

    @testset "not expect-suppressible by rule id" begin
        source = "x = 1\n"
        d = AgentRuleLint.Violation(
            AgentRuleLint.ANALYSIS_INCOMPLETE_RULE,
            :agentrulelint,
            :forbid,
            "f.jl",
            AgentRuleLint.Span(1, 1, 1, 1),
            1,
            "",
            :none,
            false,
            AgentRuleLint.analysis_incomplete_message("f.jl"),
            "i",
            "d",
        )
        diags = [d]
        expects = [
            AgentRuleLint.ExpectLine(
                1,
                AgentRuleLint.ANALYSIS_INCOMPLETE_RULE,
                "excuse long enough",
                "raw",
            ),
        ]
        AgentRuleLint.apply_expect_suppression!(diags, expects, source)
        @test !diags[1].suppressed
        @test AgentRuleLint.is_analysis_incomplete(diags[1])
    end

    @testset "project-rule fold budget emits analysis-incomplete" begin
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
            incomplete = filter(AgentRuleLint.is_analysis_incomplete, res.violations)
            @test !isempty(incomplete)
            @test all(d -> d.level == :forbid && !d.suppressed, incomplete)
            @test all(d -> d.rule_id == AgentRuleLint.ANALYSIS_INCOMPLETE_RULE, incomplete)
            @test res.exit_code != 3
            @test res.exit_code == 1
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "level cannot be weakened" begin
        root = mktempdir()
        try
            v = string(pkgversion(AgentRuleLint))
            write(
                joinpath(root, ".AgentRuleLintConfig.toml"),
                """
                agentrulelint_version = \"=$(v)\"
                [rules.analysis-incomplete]
                level = \"deny\"
                """,
            )
            @test_throws AgentRuleLint.ConfigError AgentRuleLint.resolve_policy(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "explain exists" begin
        text = AgentRuleLint.explain_rule(AgentRuleLint.ANALYSIS_INCOMPLETE_RULE; root = ROOT)
        @test occursin("analysis-incomplete", text)
        @test occursin("constant-fold", text)
    end
end
