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

    function mutation_check_no_hits(corpus_relpath)
        cmd = `julia --startup-file=no --compiled-modules=no --project=$(ROOT) -e '
            using AgentRuleLint
            res = AgentRuleLint.check(ARGS[1]; paths=[ARGS[2]])
            hits = filter(d -> d.rule_id == "silent-catch" && !d.suppressed, res.violations)
            exit(isempty(hits) ? 0 : 1)
        ' $(ROOT) $(corpus_relpath)`
        return success(run(cmd))
    end

    function with_analysis_mutation(needle::AbstractString, insert::AbstractString, corpus_relpath)
        path = joinpath(ROOT, "src", "syntax", "try_catch_analysis.jl")
        orig = read(path, String)
        mutated = replace(orig, needle => insert * needle, count = 1)
        mutated != orig || error("mutation needle not found: $needle")
        try
            write(path, mutated)
            return mutation_check_no_hits(corpus_relpath)
        finally
            write(path, orig)
        end
    end

    function with_analysis_replace(needle::AbstractString, replacement::AbstractString, corpus_relpath)
        path = joinpath(ROOT, "src", "syntax", "try_catch_analysis.jl")
        orig = read(path, String)
        mutated = replace(orig, needle => replacement, count = 1)
        mutated != orig || error("mutation needle not found: $needle")
        try
            write(path, mutated)
            return mutation_check_no_hits(corpus_relpath)
        finally
            write(path, orig)
        end
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
            write(joinpath(root, ".AgentRuleLintConfig.toml"), cfg)
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
        @test with_analysis_mutation(
            "    isempty(stmts) && return true\n",
            "    return false # MUTATION\n",
            rel("silent_catch_empty.jl"),
        )
    end

    @testset "mutation: isa-or-rethrow branch" begin
        @test silent_hits("silent_catch_or_true_evasion.jl"; suppressed = false)
        @test with_analysis_mutation(
            "    summary(node) != \"||\" && return false\n",
            "    return true # MUTATION\n",
            rel("silent_catch_or_true_evasion.jl"),
        )
    end

    @testset "mutation: macro warn-only branch" begin
        @test silent_hits("silent_catch_log_only.jl"; suppressed = false)
        @test with_analysis_replace(
            "    return summary(node) == \"macrocall\" && _macrocall_name(node, pos, src) == \"warn\"\n",
            "    return false # MUTATION\n",
            rel("silent_catch_log_only.jl"),
        )
    end

    @testset "mutation: macro name AST branch" begin
        @test silent_hits("silent_catch_info_not_warn.jl"; suppressed = false)
        @test with_analysis_replace(
            "function _macrocall_name(node::GreenNode, pos::Int, src::AbstractString)\n",
            "function _macrocall_name(node::GreenNode, pos::Int, src::AbstractString)\n    return \"warn\" # MUTATION\n",
            rel("silent_catch_info_not_warn.jl"),
        )
    end

    @testset "mutation: reachability branch" begin
        @test silent_hits("silent_catch_dead_rethrow.jl"; suppressed = false)
        @test with_analysis_replace(
            "        _stmt_unconditional_return(stmt) && (reachable = false)\n",
            "        # MUTATION reachable\n",
            rel("silent_catch_dead_rethrow.jl"),
        )
    end

    @testset "mutation: && must not propagate alone" begin
        @test silent_hits("silent_catch_and_only_interrupt.jl"; suppressed = false)
        mutated = replace(
            read(joinpath(ROOT, "src", "syntax", "try_catch_analysis.jl"), String),
            "    elseif s == \"if\"\n" =>
                "    elseif s == \"&&\"\n        return true # MUTATION\n    elseif s == \"if\"\n",
            count = 1,
        )
        path = joinpath(ROOT, "src", "syntax", "try_catch_analysis.jl")
        orig = read(path, String)
        try
            write(path, mutated)
            @test mutation_check_no_hits(rel("silent_catch_and_only_interrupt.jl"))
        finally
            write(path, orig)
        end
    end
end
