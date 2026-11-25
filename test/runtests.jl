using AgentRuleLint
using Test
using Aqua

const ROOT = dirname(@__DIR__)
const CORPUS = joinpath(ROOT, "test", "corpus")

@testset "AgentRuleLint" begin
    @testset "constant folding" begin
        src = "s = \"a\" * \"b\"\n"
        tree = AgentRuleLint.parse_source(src)
        folds = AgentRuleLint.collect_folded_string_exprs(tree, src)
        vals = [f.value for f in folds]
        @test "ab" in vals
        full = only(filter(f -> f.value == "ab", folds))
        @test full.byte_start > 0
        @test full.byte_end >= full.byte_start
    end

    @testset "reduce(*, strings) folding" begin
        hit = "x = reduce(*, [\"INT\", \"ERNAL_CODENAME\"])\n"
        tree = AgentRuleLint.parse_source(hit)
        folds = AgentRuleLint.collect_folded_string_exprs(tree, hit)
        vals = [f.value for f in folds]
        @test "INTERNAL_CODENAME" in vals
        @test "INTINT" ∉ vals

        miss = "x = reduce(*, [\"INT\", \"FOO\"])\n"
        tree2 = AgentRuleLint.parse_source(miss)
        vals2 = [f.value for f in AgentRuleLint.collect_folded_string_exprs(tree2, miss)]
        @test "INTFOO" in vals2
        @test "INTINTFOO" ∉ vals2
    end

    @testset "fold step budget" begin
        src = "a = \"x\" * \"y\"\nb = \"p\" * \"q\"\nc = \"r\" * \"s\"\n"
        tree = AgentRuleLint.parse_source(src)
        full = AgentRuleLint.collect_folded_string_exprs(tree, src)
        @test length(full) >= 3
        # Budget exhaustion returns folds collected so far (not an empty vector).
        partial = AgentRuleLint.collect_folded_string_exprs(tree, src; max_steps = 15)
        @test !isempty(partial)
        @test length(partial) < length(full)
    end

    @testset "parse fail-closed" begin
        @test_throws AgentRuleLint.ParseError AgentRuleLint.parse_source("x = (\n")
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
            res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", file)])
            hits = any(
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
                res.violations,
            )
            @test hits == want_hit
        end
    end

    @testset "expect-audit fixtures" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
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
        trail = any(
            d -> d.path == "test/corpus/trailing_expect.jl" &&
                d.rule_id == "expect-audit" &&
                occursin("trailing inline", d.message),
            res.violations,
        )
        @test trail
    end

    @testset "syntax error file fail-closed" begin
        fixtures = joinpath(ROOT, "test", "fixtures")
        mkpath(fixtures)
        bad = joinpath(fixtures, "syntax_error_tmp.jl")
        try
            write(bad, "x = (\n")
            @test_throws AgentRuleLint.ParseError AgentRuleLint.check(
                ROOT;
                paths = [joinpath("test", "fixtures", "syntax_error_tmp.jl")],
            )
        finally
            isfile(bad) && rm(bad)
        end
    end

    @testset "formatters" begin
        cs = AgentRuleLint.ConfigSource()
        d = AgentRuleLint.Violation(
            "project/test",
            :project,
            :deny,
            "test/corpus/split_string.jl",
            AgentRuleLint.Span(1, 1, 1, 10),
            1,
            "v1:abc",
            :none,
            false,
            "forbidden literal matched",
            "i",
            "d",
        )
        res = AgentRuleLint.CheckResult([d], true, 1, cs, :human, 20, 0, 1)
        io = IOContext(IOBuffer(), :color => false)
        human = AgentRuleLint.format_human(res; root = ROOT, io = io)
        @test occursin("[Project]", human)
        @test occursin("└ @ Project", human)
        @test occursin("RULE", AgentRuleLint.format_agent(res; root = ROOT))
        @test occursin("\"type\":\"header\"", replace(AgentRuleLint.format_json(res), " " => ""))
    end

    @testset "report CLI" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
        d = first(filter(x -> x.rule_id == "project/no-internal-codename" && !x.suppressed, res.violations))
        out = AgentRuleLint.format_report(d.fingerprint, d, "secret = \"x\"\n")
        @test occursin("pattern_hash", out)
        cd(ROOT) do
            @test AgentRuleLint.cli_main(["report", d.fingerprint]) == 0
            @test AgentRuleLint.cli_main(["report", "v1:000000000000000000000000000000000000000000"]) == 2
        end
    end

    @testset "CLI exit codes" begin
        cd(ROOT) do
            @test AgentRuleLint.cli_main(["explain", "expect-audit"]) == 0
            @test AgentRuleLint.cli_main(["explain", "not-a-real-rule"]) == 2
            @test AgentRuleLint.cli_main(["check", "LICENSE"]) == 0
            @test AgentRuleLint.cli_main(["check", "test/corpus/split_string.jl"]) == 1
            @test AgentRuleLint.cli_main(["nope"]) == 2
        end
    end

    @testset "agent format corpus" begin
        cd(ROOT) do
            dir = mktempdir()
            out1 = joinpath(dir, "agent1.txt")
            out2 = joinpath(dir, "agent2.txt")
            try
                @test AgentRuleLint.cli_main(
                    ["check", "--format=agent", "--output", out1, "test/corpus"],
                ) == 1
                @test AgentRuleLint.cli_main(
                    ["check", "--format=agent", "--output", out2, "test/corpus"],
                ) == 1
                text1 = read(out1, String)
                text2 = read(out2, String)
                @test !isempty(text1)
                @test text1 == text2
                @test startswith(text1, "AGENTRULELINT FAIL")
            finally
                rm(dir, recursive = true, force = true)
            end
        end
    end

    @testset "CLI subprocess -m AgentRuleLint" begin
        cmd = `julia --startup-file=no --project=$(ROOT) -m AgentRuleLint explain expect-audit`
        @test success(run(cmd))
    end

    @testset "config-from" begin
        pol = AgentRuleLint.resolve_policy(ROOT; config_from = "HEAD")
        @test pol.config_source.kind == :git_ref
        @test_throws AgentRuleLint.GitError AgentRuleLint.resolve_policy(ROOT; config_from = "not-a-ref-zzz")
    end

    include("test_fingerprint_stability.jl")
    include("test_project_rules_paths.jl")
    include("test_expect_audit.jl")
    include("test_adapter_fixes.jl")
    include("test_test_integrity.jl")
    include("test_diff_mode.jl")
    include("test_ceiling_ratchet.jl")
    include("test_diff_name_status_parser.jl")
    include("test_fail_closed_mutations.jl")
    include("test_protected_paths.jl")
    include("test_scope_paths.jl")
    include("test_config_cli_fail_closed.jl")
    include("test_output_width.jl")
    include("test_output_formats.jl")
    include("test_unsafe_boundary.jl")
    include("test_manifest_sync.jl")
    include("test_app_cli.jl")

    Aqua.test_all(AgentRuleLint)

    include("test_runic_invariance.jl")
end
