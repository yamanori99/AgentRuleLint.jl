# Guard: `src/` must not use `:human` / `:json` / `:agent` quote literals
# outside conversion functions (issue #104 PR 3). Shares scan with level/origin guards.

include(joinpath(@__DIR__, "enum_symbol_guard_common.jl"))
using .EnumSymbolGuard: scan_enum_symbol_source, collect_src_enum_symbol_violations

const _OUTPUT_FORMAT_PROBE_REL = "src/__output_format_symbol_guard_probe__.jl"
const _OUTPUT_FORMAT_NAMES = Set(["human", "json", "agent"])
const _OUTPUT_FORMAT_SYMBOL_ALLOWLIST = Tuple{String, String, String}[]

@testset "src/ OutputFormat Symbol literal guard" begin
    @testset "syntax scan finds quote literals (probe sources)" begin
        v, _ = scan_enum_symbol_source(_OUTPUT_FORMAT_PROBE_REL, "x = :json\n", _OUTPUT_FORMAT_NAMES, _OUTPUT_FORMAT_SYMBOL_ALLOWLIST)
        @test any(x -> x[3] == "json", v)
        v, _ = scan_enum_symbol_source(_OUTPUT_FORMAT_PROBE_REL, "x == :agent\n", _OUTPUT_FORMAT_NAMES, _OUTPUT_FORMAT_SYMBOL_ALLOWLIST)
        @test any(x -> x[3] == "agent", v)
        comment_only = "# :human\n"
        v, _ = scan_enum_symbol_source(_OUTPUT_FORMAT_PROBE_REL, comment_only, _OUTPUT_FORMAT_NAMES, _OUTPUT_FORMAT_SYMBOL_ALLOWLIST)
        @test isempty(v)
        str_only = "s = \":json\"\n"
        v, _ = scan_enum_symbol_source(_OUTPUT_FORMAT_PROBE_REL, str_only, _OUTPUT_FORMAT_NAMES, _OUTPUT_FORMAT_SYMBOL_ALLOWLIST)
        @test isempty(v)
        convert_fn = "function parse_enum(::Type{OutputFormat.T}, s::AbstractString)\n    x = :human\n    return x\nend\n"
        v, _ = scan_enum_symbol_source(_OUTPUT_FORMAT_PROBE_REL, convert_fn, _OUTPUT_FORMAT_NAMES, _OUTPUT_FORMAT_SYMBOL_ALLOWLIST)
        @test isempty(v)
    end

    violations, used = collect_src_enum_symbol_violations(ROOT, _OUTPUT_FORMAT_NAMES, _OUTPUT_FORMAT_SYMBOL_ALLOWLIST)
    for (file, line, name, snippet) in violations
        @error "OutputFormat Symbol literal outside conversion functions / allowlist" file line name snippet
    end
    @test isempty(violations)

    stale = [(f, id) for (f, id, _) in _OUTPUT_FORMAT_SYMBOL_ALLOWLIST if (f, id) ∉ used]
    @test isempty(stale) || error(
        "allowlist entries with no use in src/: $(join(["$f:$id" for (f, id) in stale], ", "))",
    )
end
