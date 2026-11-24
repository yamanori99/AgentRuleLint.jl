using JAILint
using Test
using Aqua

const ROOT = dirname(@__DIR__)
const CORPUS = joinpath(ROOT, "test", "corpus")

@testset "JAILint" begin
    @testset "constant folding" begin
        src = "s = \"a\" * \"b\"\n"
        tree = JAILint.parse_source(src)
        folds = JAILint.collect_folded_string_exprs(tree, src)
        vals = [f.value for f in folds]
        @test "ab" in vals
        full = only(filter(f -> f.value == "ab", folds))
        @test full.byte_start > 0
        @test full.byte_end >= full.byte_start
    end

    @testset "reduce(*, strings) folding" begin
        hit = "x = reduce(*, [\"INT\", \"ERNAL_CODENAME\"])\n"
        tree = JAILint.parse_source(hit)
        folds = JAILint.collect_folded_string_exprs(tree, hit)
        vals = [f.value for f in folds]
        @test "INTERNAL_CODENAME" in vals
        @test "INTINT" ∉ vals

        miss = "x = reduce(*, [\"INT\", \"FOO\"])\n"
        tree2 = JAILint.parse_source(miss)
        vals2 = [f.value for f in JAILint.collect_folded_string_exprs(tree2, miss)]
        @test "INTFOO" in vals2
        @test "INTINTFOO" ∉ vals2
    end

    @testset "fold step budget" begin
        src = "a = \"x\" * \"y\"\nb = \"p\" * \"q\"\nc = \"r\" * \"s\"\n"
        tree = JAILint.parse_source(src)
        full = JAILint.collect_folded_string_exprs(tree, src)
        @test length(full) >= 3
        # Budget exhaustion returns folds collected so far (not an empty vector).
        partial = JAILint.collect_folded_string_exprs(tree, src; max_steps = 15)
        @test !isempty(partial)
        @test length(partial) < length(full)
    end

    @testset "parse fail-closed" begin
        @test_throws JAILint.ParseError JAILint.parse_source("x = (\n")
    end

    @testset "corpus golden per file" begin
        expect_hits = Dict(
            "split_string.jl" => true,
            "split_star.jl" => true,
            "join_three.jl" => true,
            "expect_standalone.jl" => false,
            "utf8_multibyte.jl" => false,
            "bom_utf8.jl" => false,
            "reduce_nonconcat.jl" => false,
            "reduce_star.jl" => true,
        )
        for (file, want_hit) in expect_hits
            res = JAILint.check(ROOT; paths = [joinpath("test", "corpus", file)])
            hits = any(
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
                res.violations,
            )
            @test hits == want_hit
        end
    end

    @testset "expect-audit fixtures" begin
        res = JAILint.check(ROOT; paths = [joinpath("test", "corpus")])
        blank = any(
            d -> d.path == "test/corpus/expect_blank_line.jl" &&
                d.rule_id == "expect-audit" &&
                occursin("blank line", d.message),
            res.violations,
        )
        @test blank
        block = any(
            d -> d.path == "test/corpus/block_expect.jl" && d.rule_id == "expect-audit",
            res.violations,
        )
        @test block
    end

    @testset "syntax error file fail-closed" begin
        fixtures = joinpath(ROOT, "test", "fixtures")
        mkpath(fixtures)
        bad = joinpath(fixtures, "syntax_error_tmp.jl")
        try
            write(bad, "x = (\n")
            @test_throws JAILint.ParseError JAILint.check(
                ROOT;
                paths = [joinpath("test", "fixtures", "syntax_error_tmp.jl")],
            )
        finally
            isfile(bad) && rm(bad)
        end
    end

    @testset "formatters" begin
        cs = JAILint.ConfigSource()
        d = JAILint.Violation(
            "project/test",
            :project,
            :deny,
            "test/corpus/split_string.jl",
            JAILint.Span(1, 1, 1, 10),
            1,
            "v1:abc",
            :none,
            false,
            "forbidden literal matched",
            "i",
            "d",
        )
        res = JAILint.CheckResult([d], true, 1, cs, 20, 0, 1)
        @test occursin("┌ Error", JAILint.format_human(res; root = ROOT))
        @test occursin("RULE", JAILint.format_agent(res))
        @test occursin("\"type\":\"header\"", replace(JAILint.format_json(res), " " => ""))
    end

    @testset "report CLI" begin
        res = JAILint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
        d = first(filter(x -> x.rule_id == "project/no-internal-codename" && !x.suppressed, res.violations))
        out = JAILint.format_report(d.fingerprint, d, "secret = \"x\"\n")
        @test occursin("pattern_hash", out)
        cd(ROOT) do
            @test JAILint.cli_main(["report", d.fingerprint]) == 0
            @test JAILint.cli_main(["report", "v1:000000000000000000000000000000000000000000"]) == 2
        end
    end

    @testset "CLI exit codes" begin
        cd(ROOT) do
            @test JAILint.cli_main(["explain", "expect-audit"]) == 0
            @test JAILint.cli_main(["check", "LICENSE"]) == 0
            @test JAILint.cli_main(["check", "test/corpus/split_string.jl"]) == 1
            @test JAILint.cli_main(["nope"]) == 2
        end
    end

    @testset "CLI subprocess -m JAILint" begin
        cmd = `julia --startup-file=no --project=$(ROOT) -m JAILint explain expect-audit`
        @test success(run(cmd))
    end

    @testset "config-from" begin
        pol = JAILint.resolve_policy(ROOT; config_from = "HEAD")
        @test pol.config_source.kind == :git_ref
        @test_throws JAILint.GitError JAILint.resolve_policy(ROOT; config_from = "not-a-ref-zzz")
    end

    include("test_adapter_fixes.jl")

    Aqua.test_all(JAILint)

    include("test_runic_invariance.jl")
end
