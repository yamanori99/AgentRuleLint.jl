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
            )
            @test silent_hits(f; suppressed = false)
        end
    end

    @testset "corpus should pass" begin
        for f in (
                "silent_catch_try_finally_ok.jl",
                "silent_catch_isa_or_rethrow.jl",
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
            write(joinpath(root, ".AgentRuleLintConfig.toml"), cfg)
            write(
                joinpath(root, "log_ok.jl"),
                """
                function ok_warn(e)
                    try
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

        src_analysis = read(joinpath(ROOT, "src", "syntax", "try_catch_analysis.jl"), String)
        mutated = replace(
            src_analysis,
            "function _catch_body_swallows(" =>
                "function _catch_body_swallows(",
            count = 1,
        )
        mutated = replace(
            mutated,
            "    isempty(stmts) && return true\n" =>
                "    return false # MUTATION\n    isempty(stmts) && return true\n",
            count = 1,
        )
        try
            write(joinpath(ROOT, "src", "syntax", "try_catch_analysis.jl"), mutated)
            cmd = `julia --startup-file=no --compiled-modules=no --project=$(ROOT) -e '
                using AgentRuleLint
                res = AgentRuleLint.check(ARGS[1]; paths=["test/corpus/silent_catch_empty.jl"])
                hits = filter(d -> d.rule_id == "silent-catch" && !d.suppressed, res.violations)
                exit(isempty(hits) ? 0 : 1)
            ' $(ROOT)`
            @test success(run(cmd))
        finally
            write(joinpath(ROOT, "src", "syntax", "try_catch_analysis.jl"), src_analysis)
        end
    end
end
