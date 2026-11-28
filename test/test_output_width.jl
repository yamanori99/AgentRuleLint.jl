using AgentRuleLint
using Test

# ROOT comes from ParallelTestRunner init_code in test/runtests.jl.

const textwidth = Base.Unicode.textwidth

function ansi_stripped_lines(text::AbstractString)
    return split(replace(text, r"\e\[[0-9;]*m" => ""), '\n'; keepempty = false)
end

function is_status_header_line(line::AbstractString)
    return startswith(line, "AGENTRULELINT ") || startswith(line, "AgentRuleLint v")
end

function is_summary_line(line::AbstractString)
    return startswith(line, "Summary:")
end

function is_code_gutter_line(line::AbstractString)
    return occursin("> ", line)
end

function assert_max_textwidth(
        text::AbstractString,
        limit::Int;
        skip_status_headers::Bool = false,
        skip_summary::Bool = false,
        skip_code_gutter::Bool = false,
    )
    for line in ansi_stripped_lines(text)
        skip_status_headers && is_status_header_line(line) && continue
        skip_summary && is_summary_line(line) && continue
        skip_code_gutter && is_code_gutter_line(line) && continue
        @test textwidth(line) <= limit
    end
    return nothing
end

function human_code_gutter_lines(text::AbstractString)
    return filter(l -> occursin("> ", l), split(text, '\n'; keepempty = false))
end

function with_columns(f, columns::Union{Nothing, Int})
    cols = columns === nothing ? nothing : string(columns)
    return withenv(f, "COLUMNS" => cols)
end

function corpus_human_text(columns::Union{Nothing, Int})
    return with_columns(
        () -> begin
            res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
            AgentRuleLint.format_human(res; root = ROOT, io = IOContext(IOBuffer(), :color => false))
        end,
        columns,
    )
end

function corpus_agent_text(columns::Union{Nothing, Int})
    return with_columns(
        () -> begin
            res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
            AgentRuleLint.format_agent(res; root = ROOT, io = IOContext(IOBuffer(), :color => false))
        end,
        columns,
    )
end

@testset "output width" begin
    @testset "non-TTY human output is identical across COLUMNS" begin
        outs = [corpus_human_text(c) for c in (nothing, 40, 200)]
        @test all(o -> o == outs[1], outs)
    end

    @testset "agent output is identical across COLUMNS" begin
        outs = [corpus_agent_text(c) for c in (nothing, 40, 200)]
        @test all(o -> o == outs[1], outs)
    end

    @testset "corpus human respects pinned output_width and 80 cap" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
        plain = IOContext(IOBuffer(), :color => false)
        out60 = AgentRuleLint.format_human(res; root = ROOT, io = plain, output_width = 60)
        assert_max_textwidth(
            out60,
            60;
            skip_status_headers = true,
            skip_summary = true,
            skip_code_gutter = true,
        )
        out80 = AgentRuleLint.format_human(res; root = ROOT, io = plain, output_width = 80)
        assert_max_textwidth(
            out80,
            80;
            skip_status_headers = true,
            skip_summary = true,
            skip_code_gutter = true,
        )
    end

    @testset "long do_not wraps with aligned prefix" begin
        long_dn = join(fill("word", 24), " ")
        d = AgentRuleLint.Violation(
            "project/test",
            AgentRuleLint.Origin.PROJECT,
            AgentRuleLint.Level.DENY,
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
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), AgentRuleLint.OutputFormat.HUMAN, 20, 0, 1)
        out = AgentRuleLint.format_human(res; root = ROOT, output_width = 32)
        lines = filter(!isempty, split(out, '\n'))
        do_lines = filter(l -> occursin("do_not:", l) || occursin(r"^│\s{7,}", l), lines)
        @test length(do_lines) >= 2
    end

    @testset "long source line caps gutter excerpt at AGENT_EXCERPT_CAP" begin
        long_line = "x"^120
        fixture_root = mktempdir()
        rel = "tmp_human_width/x.jl"
        cap = AgentRuleLint.AGENT_EXCERPT_CAP
        try
            mkpath(joinpath(fixture_root, "tmp_human_width"))
            write(joinpath(fixture_root, rel), long_line * "\n")
            d = AgentRuleLint.Violation(
                "project/test",
                AgentRuleLint.Origin.PROJECT,
                AgentRuleLint.Level.DENY,
                rel,
                AgentRuleLint.Span(1, 1, 1, 120),
                1,
                "v1:abc",
                :none,
                false,
                "forbidden literal matched",
                "",
                "",
            )
            res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), AgentRuleLint.OutputFormat.HUMAN, 20, 0, 1)
            plain = IOContext(IOBuffer(), :color => false)
            out_pipe = AgentRuleLint.format_human(res; root = fixture_root, io = plain)
            out_tty = AgentRuleLint.format_human(
                res;
                root = fixture_root,
                io = plain,
                output_width = 35,
            )
            @test human_code_gutter_lines(out_pipe) == human_code_gutter_lines(out_tty)
            src_line = only(human_code_gutter_lines(out_pipe))
            excerpt, _, omitted = AgentRuleLint._human_gutter_excerpt(long_line, cap)
            @test endswith(src_line, " (+$omitted chars omitted)")
            @test occursin(excerpt, src_line)
            @test textwidth(excerpt) <= cap
        finally
            rm(fixture_root, recursive = true, force = true)
        end
    end

    @testset "fold-budget corpus gutter capped on pipe and pinned width" begin
        path = joinpath("test", "corpus", "test_integrity_fold_budget.jl")
        res = AgentRuleLint.check(ROOT; paths = [path])
        plain = IOContext(IOBuffer(), :color => false)
        cap = AgentRuleLint.AGENT_EXCERPT_CAP
        out_pipe = AgentRuleLint.format_human(res; root = ROOT, io = plain)
        out_pinned = AgentRuleLint.format_human(
            res;
            root = ROOT,
            io = plain,
            output_width = cap,
        )
        gutters_pipe = human_code_gutter_lines(out_pipe)
        gutters_pin = human_code_gutter_lines(out_pinned)
        @test gutters_pipe == gutters_pin
        src_line = only(gutters_pipe)
        @test length(src_line) < 500
        @test occursin("chars omitted)", src_line)
        body_part = split(src_line, "> "; limit = 2)[2]
        snippet = split(body_part, " (+"; limit = 2)[1]
        @test textwidth(snippet) <= cap
    end

    @testset "CJK prose wraps by textwidth" begin
        cjk = "日本語"^20
        d = AgentRuleLint.Violation(
            "project/test",
            AgentRuleLint.Origin.PROJECT,
            AgentRuleLint.Level.DENY,
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
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), AgentRuleLint.OutputFormat.HUMAN, 20, 0, 1)
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
            AgentRuleLint.Origin.PROJECT,
            AgentRuleLint.Level.DENY,
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
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), AgentRuleLint.OutputFormat.HUMAN, 20, 0, 1)
        loc_needle = "very/long/path/under/test/corpus/example_name.jl:9:9-9:9"
        out = AgentRuleLint.format_human(res; root = ROOT, output_width = 80)
        @test occursin(loc_needle, out)
    end

    @testset "json output unchanged" begin
        d = AgentRuleLint.Violation(
            "project/test",
            AgentRuleLint.Origin.PROJECT,
            AgentRuleLint.Level.DENY,
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
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), AgentRuleLint.OutputFormat.HUMAN, 20, 0, 1)
        js = AgentRuleLint.format_json(res)
        @test occursin("\"type\":\"header\"", replace(js, " " => ""))
        @test !occursin("…", js)
        for line in split(js, '\n'; keepempty = false)
            @test !occursin('│', line)
        end
    end

    @testset "agent HIT lines never wrap (no continuation indent)" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
        out = AgentRuleLint.format_agent(res; root = ROOT, io = IOBuffer())
        for line in split(out, '\n'; keepempty = false)
            occursin(r"^HIT .+ \| ", line) || continue
            @test !occursin(r"^ +", line)
        end
    end

    @testset "agent keeps path and message; caps source excerpt only" begin
        long_path = join(["segment" for _ in 1:24], "/") * ".jl"
        long_msg = "diagnostic-message-" * ('m'^180)
        d = AgentRuleLint.Violation(
            "project/test",
            AgentRuleLint.Origin.PROJECT,
            AgentRuleLint.Level.DENY,
            long_path,
            AgentRuleLint.Span(2, 2, 2, 5),
            2,
            "v1:agentmeta",
            :none,
            false,
            long_msg,
            "short intent",
            "short do_not",
        )
        res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), AgentRuleLint.OutputFormat.AGENT, 20, 0, 1)
        out = AgentRuleLint.format_agent(res; root = ROOT, io = IOBuffer())
        loc = "$long_path:2:2-2:5"
        @test occursin("RULE ", out)
        @test occursin(long_path, out)
        @test occursin(loc, out)
        @test occursin(long_msg, out)
        @test occursin("intent: short intent", out)
        @test occursin("do_not: short do_not", out)
        hit_lines = filter(l -> startswith(l, "HIT "), split(out, '\n'; keepempty = false))
        @test length(hit_lines) == 1
        @test hit_lines[1] == "HIT $loc | $long_msg"
    end

    @testset "agent caps long source excerpt with ellipsis" begin
        excerpt_cap = 24
        body = "secret"^40
        fixture_root = mktempdir()
        rel = "tmp_agent_excerpt/line.jl"
        try
            mkpath(joinpath(fixture_root, "tmp_agent_excerpt"))
            write(joinpath(fixture_root, rel), body * "\n")
            d = AgentRuleLint.Violation(
                "project/test",
                AgentRuleLint.Origin.PROJECT,
                AgentRuleLint.Level.DENY,
                rel,
                AgentRuleLint.Span(1, 1, 1, length(body)),
                1,
                "v1:snip",
                :none,
                false,
                "unused when snippet present",
                "",
                "",
            )
            res = AgentRuleLint.CheckResult([d], true, 1, AgentRuleLint.ConfigSource(), AgentRuleLint.OutputFormat.AGENT, 20, 0, 1)
            out = AgentRuleLint.format_agent(
                res;
                root = fixture_root,
                io = IOBuffer(),
                output_width = excerpt_cap,
            )
            hit = only(filter(l -> startswith(l, "HIT "), split(out, '\n'; keepempty = false)))
            loc = "$rel:1:1-1:$(length(body))"
            @test startswith(hit, "HIT $loc | ")
            excerpt = split(hit, " | "; limit = 2)[2]
            @test textwidth(excerpt) <= excerpt_cap
            @test endswith(excerpt, "…")
            @test excerpt != body
        finally
            rm(fixture_root; recursive = true, force = true)
        end
    end

    @testset "human pinned output_width still wraps" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
        out = AgentRuleLint.format_human(
            res;
            root = ROOT,
            io = IOContext(IOBuffer(), :color => false),
            output_width = 72,
        )
        assert_max_textwidth(
            out,
            72;
            skip_status_headers = true,
            skip_summary = true,
            skip_code_gutter = true,
        )
    end

    @testset "summary verdict stays one line at narrow width with CLI override" begin
        root = mktempdir()
        old = pwd()
        try
            v = string(pkgversion(AgentRuleLint))
            cfg = joinpath(root, ".AgentRuleLint.jl.toml")
            write(
                cfg,
                """
                agentrulelint_version = \"=$(v)\"
                default_format = \"human\"
                [rules.expect-audit]
                level = \"forbid\"
                on_allow_rule = \"warn\"
                [rules.unsafe-boundary]
                level = \"warn\"
                allow_modules = []
                allow_globs = []
                """,
            )
            cd(ROOT)
            res = AgentRuleLint.check(
                ROOT;
                paths = [joinpath("test", "corpus", "unsafe_allow_module.jl")],
                config_path = cfg,
                exit_severity = :forbid,
            )
            out = AgentRuleLint.format_human(
                res;
                root = ROOT,
                io = IOContext(IOBuffer(), :color => false),
                output_width = 40,
            )
            summary_lines = filter(is_summary_line, ansi_stripped_lines(out))
            @test length(summary_lines) == 1
            s = summary_lines[1]
            @test occursin("threshold forbid from --exit-severity", s)
            @test occursin("below threshold", s)
            assert_max_textwidth(out, 40; skip_status_headers = true, skip_summary = true)
        finally
            cd(old)
            rm(root, recursive = true, force = true)
        end
    end

end
