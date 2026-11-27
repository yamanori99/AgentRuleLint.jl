@testset "silent-catch rule" begin
    rel(p) = joinpath("test", "corpus", p)

    function silent_hits(path; suppressed = nothing)
        res = AgentRuleLint.check(ROOT; paths = [rel(path)])
        hits = filter(d -> d.rule_id == "silent-catch" && d.path == rel(path), res.violations)
        unsup = filter(!d -> d.suppressed, hits)
        sup = filter(d -> d.suppressed, hits)
        if suppressed === true
            return !isempty(sup) && isempty(unsup)
        elseif suppressed === false
            return !isempty(unsup)
        end
        return !isempty(hits)
    end

    @testset "corpus should flag" begin
        for f in (
                "silent_catch_empty.jl",
                "silent_catch_underscore_nothing.jl",
                "silent_catch_log_only.jl",
                "silent_catch_branch_evasion.jl",
                "silent_catch_nested.jl",
                "silent_catch_assign_default.jl",
                "silent_catch_and_only_interrupt.jl",
                "silent_catch_or_true_evasion.jl",
                "silent_catch_fake_emit.jl",
                "silent_catch_info_not_warn.jl",
                "silent_catch_dead_rethrow.jl",
            )
            @test silent_hits(f; suppressed = false)
        end
    end

    @testset "corpus should pass" begin
        for f in (
                "silent_catch_try_finally_ok.jl",
                "silent_catch_isa_or_rethrow.jl",
                "silent_catch_isa_call_or_rethrow.jl",
                "silent_catch_if_else_rethrow.jl",
                "silent_catch_interrupt_then_throw.jl",
            )
            @test !silent_hits(f; suppressed = false)
        end
    end

    @testset "expect suppresses anchored try" begin
        @test silent_hits("expect_anchor_try_ok.jl"; suppressed = true)
    end

    @testset "warn_counts_as_handling" begin
        root = mktempdir()
        try
            ver = string(pkgversion(AgentRuleLint))
            cfg = """
            agentrulelint_version = \"=$(ver)\"

            [rules.silent-catch]
            level = \"deny\"
            warn_counts_as_handling = true
            """
            write(joinpath(root, ".AgentRuleLint.jl.toml"), cfg)
            write(
                joinpath(root, "log_ok.jl"),
                """
                function ok_warn(e)
                    return try
                        risky()
                    catch e
                        @warn \"msg\" exception = e
                    end
                end
                """,
            )
            res = AgentRuleLint.check(root; paths = ["log_ok.jl"])
            hits = filter(d -> d.rule_id == "silent-catch" && !d.suppressed, res.violations)
            @test isempty(hits)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "mutation: disabled swallow detection" begin
        res = AgentRuleLint.check(ROOT; paths = [rel("silent_catch_empty.jl")])
        @test any(d -> d.rule_id == "silent-catch" && !d.suppressed, res.violations)
    end

    @testset "mutation: isa-or-rethrow branch" begin
        @test silent_hits("silent_catch_or_true_evasion.jl"; suppressed = false)
    end

    @testset "macro detection uses macro_name AST" begin
        src = "try x() catch err\n        @info \"@warn\" exception = err\n    end\n"
        tree = AgentRuleLint.parse_source(src)
        site = only(AgentRuleLint.collect_try_catch_sites(tree, src))
        body = site.catch_body
        body !== nothing || error("expected catch body")
        stmt, sp = only(AgentRuleLint._block_statements(body, site.catch_body_pos))
        @test AgentRuleLint._macrocall_name(stmt, sp, src) == "info"
        @test !AgentRuleLint._macro_is_warn(stmt, sp, src)
        @test silent_hits("silent_catch_info_not_warn.jl"; suppressed = false)
    end

    @testset "mutation: reachability branch" begin
        @test silent_hits("silent_catch_dead_rethrow.jl"; suppressed = false)
    end

    @testset "mutation: && must not propagate alone" begin
        @test silent_hits("silent_catch_and_only_interrupt.jl"; suppressed = false)
    end
end
