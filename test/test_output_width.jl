using AgentRuleLint
using Test
const textwidth = Base.Unicode.textwidth

const ROOT = dirname(@__DIR__)

function ansi_stripped_lines(text::AbstractString)
    return split(replace(text, r"\e\[[0-9;]*m" => ""), '\n'; keepempty = false)
end

function assert_max_textwidth(text::AbstractString, limit::Int)
    for line in ansi_stripped_lines(text)
        @test textwidth(line) <= limit
    end
    return nothing
end

function corpus_human_text(columns::Int)
    old = get(ENV, "COLUMNS", nothing)
    ENV["COLUMNS"] = string(columns)
    try
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
        return AgentRuleLint.format_human(res; root = ROOT, io = IOContext(IOBuffer(), :color => false))
    finally
        if old === nothing
            pop!(ENV, "COLUMNS", nothing)
        else
            ENV["COLUMNS"] = old
        end
    end
end

@testset "output width" begin
    @testset "corpus human respects COLUMNS and 80 cap" begin
        out60 = corpus_human_text(60)
        assert_max_textwidth(out60, 60)
        out200 = corpus_human_text(200)
        assert_max_textwidth(out200, 80)
    end

    @testset "long do_not wraps with aligned prefix" begin
        long_dn = join(fill("word", 24), " ")
        d = AgentRuleLint.Violation(
            "project/test",
            :project,
            :deny,
            "x.jl",
            AgentRuleLint.Span(1, 1, 1, 3),
            1,
            "v1:abc",
            :none,
            false,
            "msg",
            "intent",
            long_dn,
        )
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), :human, 20, 0, 1)
        out = AgentRuleLint.format_human(res; root = ROOT, output_width = 32)
        lines = filter(!isempty, split(out, '\n'))
        do_lines = filter(l -> occursin("do_not:", l) || occursin(r"^│\s{7,}", l), lines)
        @test length(do_lines) >= 2
    end

    @testset "long source line truncates in gutter" begin
        long_line = "x"^120
        d = AgentRuleLint.Violation(
            "project/test",
            :project,
            :deny,
            "tmp_human_width/x.jl",
            AgentRuleLint.Span(1, 1, 1, 120),
            1,
            "v1:abc",
            :none,
            false,
            "forbidden literal matched",
            "",
            "",
        )
        mkpath(joinpath(ROOT, "tmp_human_width"))
        write(joinpath(ROOT, "tmp_human_width", "x.jl"), long_line * "\n")
        try
            res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), :human, 20, 0, 1)
            out = AgentRuleLint.format_human(res; root = ROOT, output_width = 35)
            gutter_lines = filter(l -> occursin(" │ ", l), split(out, '\n'))
            @test !isempty(gutter_lines)
            @test all(textwidth.(AgentRuleLint.strip_ansi.(gutter_lines)) .<= 35)
            @test any(l -> endswith(strip(l), "…"), gutter_lines)
            @test !any(l -> textwidth(l) > 35, gutter_lines)
        finally
            rm(joinpath(ROOT, "tmp_human_width"), recursive = true, force = true)
        end
    end

    @testset "CJK prose wraps by textwidth" begin
        cjk = "日本語"^20
        d = AgentRuleLint.Violation(
            "project/test",
            :project,
            :deny,
            "x.jl",
            AgentRuleLint.Span(1, 1, 1, 1),
            1,
            "v1:x",
            :none,
            false,
            "msg",
            cjk,
            "",
        )
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), :human, 20, 0, 1)
        out = AgentRuleLint.format_human(res; root = ROOT, output_width = 24)
        intent_lines = filter(l -> occursin("intent:", l) || occursin(r"^│\s{7,}", l), split(out, '\n'))
        @test length(intent_lines) >= 2
        @test all(textwidth.(intent_lines) .<= 24)
    end

    @testset "UTF-8 wrap and truncate at wide-character boundaries" begin
        only_wide = "🙂"^12
        line = AgentRuleLint.truncate_quoted_line("│     > ", only_wide, 10)
        @test textwidth(line) <= 10
        @test endswith(strip(line), "…")

        only_cjk = "日本語日本語日本"
        line2 = AgentRuleLint.truncate_quoted_line("> ", only_cjk, 8)
        @test textwidth(line2) <= 8
        @test endswith(strip(line2), "…")
    end

    @testset "locations are not truncated" begin
        d = AgentRuleLint.Violation(
            "project/test",
            :project,
            :deny,
            "very/long/path/under/test/corpus/example_name.jl",
            AgentRuleLint.Span(9, 9, 9, 9),
            1,
            "v1:loc",
            :none,
            false,
            "m",
            "",
            "",
        )
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), :human, 20, 0, 1)
        loc_needle = "very/long/path/under/test/corpus/example_name.jl:9:9-9:9"
        out = AgentRuleLint.format_human(res; root = ROOT, output_width = 80)
        @test occursin(loc_needle, out)
    end

    @testset "json output unchanged" begin
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
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), :human, 20, 0, 1)
        js = AgentRuleLint.format_json(res)
        @test occursin("\"type\":\"header\"", replace(js, " " => ""))
        @test !occursin("…", js)
        for line in split(js, '\n'; keepempty = false)
            @test !occursin('│', line)
        end
    end

    @testset "agent format width (single violation fixture)" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
        out = AgentRuleLint.format_agent(res; root = ROOT, io = IOBuffer(), output_width = 60)
        assert_max_textwidth(out, 60)
    end

end
