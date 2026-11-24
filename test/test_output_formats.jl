using AgentRuleLint
using JSON3
using Test

const ROOT = dirname(@__DIR__)
const SCHEMA_PATH = joinpath(ROOT, "schemas", "check-jsonl.schema.json")

function strip_ansi_local(s::AbstractString)
    return AgentRuleLint.strip_ansi(s)
end

function check_result_fixture()
    cs = AgentRuleLint.ConfigSource(:path, ".AgentRuleLintConfig.toml", "", "")
    d = AgentRuleLint.Violation(
        "project/no-internal-codename",
        :project,
        :deny,
        "test/corpus/split_string.jl",
        AgentRuleLint.Span(1, 1, 1, 10),
        1,
        "v1:abc",
        :none,
        false,
        "forbidden literal matched",
        "Keep internal codenames out of public package files.",
        "Do not split strings to evade.",
    )
    return AgentRuleLint.CheckResult([d], true, 1, cs, :human, 20, 0, 1)
end

function jsonl_record(line::AbstractString)::Dict{String, Any}
    return JSON3.read(line, Dict{String, Any})
end

function validate_jsonl_schema!(text::AbstractString)
    JSON3.read(read(SCHEMA_PATH, String))
    lines = split(strip(text), '\n')
    length(lines) >= 2 || error("expected header, diagnostics, and summary lines")
    kinds = String[]
    for (i, line) in enumerate(lines)
        obj = jsonl_record(line)
        t = String(obj["type"])
        push!(kinds, t)
        if t == "header"
            @test obj["version"] isa AbstractString
            @test String(obj["position_encoding"]) == "utf8-codepoint-1based"
        elseif t == "diagnostic"
            @test haskey(obj, "rule_id")
            @test haskey(obj, "span")
        elseif t == "summary"
            @test obj["exit_code"] isa Integer
        else
            error("unknown record type $t at line $i")
        end
    end
    @test kinds[1] == "header"
    @test kinds[end] == "summary"
    return nothing
end

@testset "output formats and color" begin
    @testset "agent and json ignore IO color" begin
        res = check_result_fixture()
        plain_agent = AgentRuleLint.format_agent(res; root = ROOT, io = IOContext(IOBuffer(), :color => false))
        color_agent = AgentRuleLint.format_agent(res; root = ROOT, io = IOContext(IOBuffer(), :color => true))
        @test plain_agent == color_agent
        json_a = AgentRuleLint.format_json(res)
        json_b = AgentRuleLint.format_json(res)
        @test json_a == json_b
        @test !occursin("\e[", json_a)
    end

    @testset "human color strips to plain" begin
        res = check_result_fixture()
        plain = AgentRuleLint.format_human(res; root = ROOT, io = IOContext(IOBuffer(), :color => false))
        colored = AgentRuleLint.format_human(res; root = ROOT, io = IOContext(IOBuffer(), :color => true))
        @test strip_ansi_local(colored) == plain
        @test occursin("\e[36m", colored)
        @test occursin("\e[31m", colored)
    end

    @testset "json schema validation" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
        js = AgentRuleLint.format_json(res)
        validate_jsonl_schema!(js)
        @test occursin("\"version\"", replace(js, " " => ""))
    end

    @testset "json diagnostic sort order" begin
        cs = AgentRuleLint.ConfigSource()
        z = AgentRuleLint.Violation(
            "r",
            :project,
            :deny,
            "z/z.jl",
            AgentRuleLint.Span(1, 1, 1, 1),
            1,
            "v1:z",
            :none,
            false,
            "z-msg",
            "",
            "",
        )
        a = AgentRuleLint.Violation(
            "r",
            :project,
            :deny,
            "a/a.jl",
            AgentRuleLint.Span(1, 1, 1, 1),
            1,
            "v1:a",
            :none,
            false,
            "a-msg",
            "",
            "",
        )
        res = AgentRuleLint.CheckResult([z, a], true, 1, cs, :human, 20, 0, 2)
        paths = String[]
        for line in split(AgentRuleLint.format_json(res), '\n'; keepempty = false)
            obj = jsonl_record(line)
            String(obj["type"]) == "diagnostic" || continue
            push!(paths, String(obj["path"]))
        end
        @test paths == String["a/a.jl", "z/z.jl"]
    end

    @testset "explain and report exit codes" begin
        cd(ROOT) do
            @test AgentRuleLint.cli_main(["explain", "project/no-internal-codename"]) == 0
            @test AgentRuleLint.cli_main(["explain", "expect-audit"]) == 0
            @test AgentRuleLint.cli_main(["explain", "no-such-rule"]) == 2
            @test AgentRuleLint.cli_main(["explain", "protected-paths"]) == 0
        end
    end

    @testset "ceiling dash without ratchet file" begin
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
        human = AgentRuleLint.format_human(res; root = ROOT, io = IOContext(IOBuffer(), :color => false))
        agent = AgentRuleLint.format_agent(res; root = ROOT, io = IOContext(IOBuffer(), :color => false))
        @test occursin("ceiling 0)", human)
        @test occursin("ceiling=-", agent)
    end

    @testset "human framed layout golden" begin
        paths = [
            joinpath("test", "corpus", "block_expect.jl"),
            joinpath("test", "corpus", "split_string.jl"),
        ]
        res = AgentRuleLint.check(ROOT; paths = paths)
        io = IOContext(IOBuffer(), :color => false)
        out = AgentRuleLint.format_human(res; root = ROOT, io = io)
        @test occursin("AgentRuleLint v", out)
        @test occursin("utf8-codepoint-1based", out)
        @test occursin("┌ Error:", out)
        @test occursin("└ @ AgentRuleLint", out)
        @test occursin("└ @ Project", out)
        @test occursin("block comment expect forbidden", out)
        @test occursin("forbidden literal matched", out)
        @test occursin("│", out)
        @test occursin(" │ ", out)
        @test occursin("Summary:", out)
        @test occursin("FAILED", out) && occursin("exit 1", out)
        @test occursin("~~~~~~~~~~~~~~~~~~~~~~~~", out)
        ul_lines = [l for l in split(out, '\n') if occursin('~', l)]
        @test any(
            l -> begin
                m = match(r"~+", l)
                return m !== nothing && length(m.match) == 24
            end,
            ul_lines,
        )
        @test !any(l -> occursin(r"~{80,}", l), ul_lines)
    end

    @testset "human COLUMNS=60 code lines never wrap" begin
        old = get(ENV, "COLUMNS", nothing)
        ENV["COLUMNS"] = "60"
        try
            res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
            out = AgentRuleLint.format_human(res; root = ROOT, io = IOContext(IOBuffer(), :color => false))
            for line in split(out, '\n'; keepempty = false)
                occursin(" │ ", line) || continue
                @test Base.Unicode.textwidth(AgentRuleLint.strip_ansi(line)) <= 60
                @test count('~', line) <= 60
            end
        finally
            old === nothing ? pop!(ENV, "COLUMNS", nothing) : (ENV["COLUMNS"] = old)
        end
    end

    @testset "explain uses registry docs" begin
        audit = AgentRuleLint.explain_rule("expect-audit"; root = ROOT)
        @test occursin("agentrulelint-expect: expect-audit", audit)
        @test occursin("level: forbid", audit)
        paths = AgentRuleLint.explain_rule("protected-paths"; root = ROOT)
        @test occursin("rule_id: protected-paths", paths)
        @test occursin("Protect designated policy, lockfiles, and workflow paths", paths)
        @test occursin("Edit protected files, weaken compat, or rename paths", paths)
    end
end
