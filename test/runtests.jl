using JAILint
using Test
using Aqua

const CORPUS = joinpath(@__DIR__, "corpus")

@testset "JAILint" begin
    @testset "types" begin
        d = JAILint.Diagnostic(
            "JA004",
            :jailint,
            :forbid,
            "a.jl",
            JAILint.Span(1, 1, 1, 2),
            1,
            "v1:abc",
            :none,
            false,
            "msg",
            "",
            "",
        )
        @test d.rule_id == "JA004"
    end

    @testset "config" begin
        root = dirname(@__DIR__)
        pol = JAILint.resolve_policy(root)
        @test pol.jailint_version.minor == 1
    end

    @testset "syntax constant folder" begin
        src = "s = \"a\" * \"b\"\n"
        tree = JAILint.parse_source(src)
        vals = JAILint.folded_string_literals(tree, JAILint.normalize_source(src))
        @test any(==("ab"), vals) || any(v -> occursin("a", v), vals)
    end

    @testset "json formatter" begin
        res = JAILint.CheckResult(JAILint.Diagnostic[], true, 0, Dict{String, Any}(), 0, 0)
        out = JAILint.format_json(res)
        @test occursin("\"type\":\"header\"", replace(out, " " => ""))
    end

    @testset "expect audit" begin
        root = mktempdir()
        bad = joinpath(root, "bad.jl")
        write(bad, "x = 1 # jailint-expect: JA004 reason=\"nope\"\n")
        res = JAILint.run_check(root; paths = [bad])
        @test any(d -> d.rule_id == "JA004" && !d.suppressed, res.diagnostics)
    end

    @testset "corpus golden" begin
        root = dirname(@__DIR__)
        res = JAILint.run_check(root; paths = [joinpath("test", "corpus")])
        @test res.complete
        has_violation = any(d -> !d.suppressed && d.rule_id == "JP:no-internal-codename", res.diagnostics)
        @test has_violation
    end

    @testset "CLI exit codes" begin
        root = dirname(@__DIR__)
        @test JAILint.main(["explain", "JA004"]) == 0
        @test JAILint.main(["check", "LICENSE"]) == 0
    end

    Aqua.test_all(JAILint; ambiguities = false, unbound_args = false)

    include("test_runic_invariance.jl")
end
