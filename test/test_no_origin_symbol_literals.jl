# Guard: `src/` must not use `:agentrulelint` / `:preset` / `:project` quote literals
# outside conversion functions (issue #104 PR 2). Shares scan with level guard.

include(joinpath(@__DIR__, "enum_symbol_guard_common.jl"))
using .EnumSymbolGuard: scan_enum_symbol_source, collect_src_enum_symbol_violations

const _ORIGIN_PROBE_REL = "src/__origin_symbol_guard_probe__.jl"
const _ORIGIN_NAMES = Set(["agentrulelint", "preset", "project"])
const _ORIGIN_SYMBOL_ALLOWLIST = Tuple{String, String, String}[]

@testset "src/ Origin Symbol literal guard" begin
    @testset "syntax scan finds quote literals (probe sources)" begin
        v, _ = scan_enum_symbol_source(_ORIGIN_PROBE_REL, "x = :preset\n", _ORIGIN_NAMES, _ORIGIN_SYMBOL_ALLOWLIST)
        @test any(x -> x[3] == "preset", v)
        v, _ = scan_enum_symbol_source(_ORIGIN_PROBE_REL, "x == :project\n", _ORIGIN_NAMES, _ORIGIN_SYMBOL_ALLOWLIST)
        @test any(x -> x[3] == "project", v)
        comment_only = "# :agentrulelint\n"
        v, _ = scan_enum_symbol_source(_ORIGIN_PROBE_REL, comment_only, _ORIGIN_NAMES, _ORIGIN_SYMBOL_ALLOWLIST)
        @test isempty(v)
        str_only = "s = \":preset\"\n"
        v, _ = scan_enum_symbol_source(_ORIGIN_PROBE_REL, str_only, _ORIGIN_NAMES, _ORIGIN_SYMBOL_ALLOWLIST)
        @test isempty(v)
        convert_fn = "function parse_enum(::Type{Origin.T}, s::AbstractString)\n    x = :project\n    return x\nend\n"
        v, _ = scan_enum_symbol_source(_ORIGIN_PROBE_REL, convert_fn, _ORIGIN_NAMES, _ORIGIN_SYMBOL_ALLOWLIST)
        @test isempty(v)
    end

    violations, used = collect_src_enum_symbol_violations(ROOT, _ORIGIN_NAMES, _ORIGIN_SYMBOL_ALLOWLIST)
    for (file, line, name, snippet) in violations
        @error "Origin Symbol literal outside conversion functions / allowlist" file line name snippet
    end
    @test isempty(violations)

    stale = [(f, id) for (f, id, _) in _ORIGIN_SYMBOL_ALLOWLIST if (f, id) ∉ used]
    @test isempty(stale) || error(
        "allowlist entries with no use in src/: $(join(["$f:$id" for (f, id) in stale], ", "))",
    )
end
