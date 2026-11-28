# Guard: `src/` must not use `:forbid` / `:deny` / `:warn` / `:allow` quote literals
# outside conversion functions (issue #104). Syntax scan via parse_source.

include(joinpath(@__DIR__, "enum_symbol_guard_common.jl"))
using .EnumSymbolGuard: scan_enum_symbol_source, collect_src_enum_symbol_violations

const _LEVEL_PROBE_REL = "src/__level_symbol_guard_probe__.jl"
const _LEVEL_NAMES = Set(["forbid", "deny", "warn", "allow"])
const _LEVEL_SYMBOL_ALLOWLIST = Tuple{String, String, String}[]

@testset "src/ Level Symbol literal guard" begin
    @testset "syntax scan finds quote literals (probe sources)" begin
        v, _ = scan_enum_symbol_source(_LEVEL_PROBE_REL, "x = :forbid\n", _LEVEL_NAMES, _LEVEL_SYMBOL_ALLOWLIST)
        @test any(x -> x[2] == 1 && x[3] == "forbid", v)
        v, _ = scan_enum_symbol_source(_LEVEL_PROBE_REL, "x == :deny\n", _LEVEL_NAMES, _LEVEL_SYMBOL_ALLOWLIST)
        @test any(x -> x[3] == "deny", v)
        comment_only = "# :warn\n"
        v, _ = scan_enum_symbol_source(_LEVEL_PROBE_REL, comment_only, _LEVEL_NAMES, _LEVEL_SYMBOL_ALLOWLIST)
        @test isempty(v)
        str_only = "s = \":allow\"\n"
        v, _ = scan_enum_symbol_source(_LEVEL_PROBE_REL, str_only, _LEVEL_NAMES, _LEVEL_SYMBOL_ALLOWLIST)
        @test isempty(v)
        convert_fn = "function parse_enum(::Type{Level.T}, s::AbstractString)\n    x = :forbid\n    return x\nend\n"
        v, _ = scan_enum_symbol_source(_LEVEL_PROBE_REL, convert_fn, _LEVEL_NAMES, _LEVEL_SYMBOL_ALLOWLIST)
        @test isempty(v)
    end

    violations, used = collect_src_enum_symbol_violations(ROOT, _LEVEL_NAMES, _LEVEL_SYMBOL_ALLOWLIST)
    for (file, line, name, snippet) in violations
        @error "Level Symbol literal outside conversion functions / allowlist" file line name snippet
    end
    @test isempty(violations)

    stale = [(f, id) for (f, id, _) in _LEVEL_SYMBOL_ALLOWLIST if (f, id) ∉ used]
    @test isempty(stale) || error(
        "allowlist entries with no use in src/: $(join(["$f:$id" for (f, id) in stale], ", "))",
    )
end
