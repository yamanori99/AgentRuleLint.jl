# Guard: `src/` must not use `:forbid` / `:deny` / `:warn` / `:allow` quote literals
# outside conversion functions (issue #104). Syntax scan via parse_source.

const _LEVEL_SRC_ROOT = joinpath(ROOT, "src")
const _LEVEL_PROBE_REL = "src/__level_symbol_guard_probe__.jl"
const _LEVEL_NAMES = Set(["forbid", "deny", "warn", "allow"])

# (relpath under repo, identifier, reason) — remaining Symbol uses for exit_severity
# until a later #104 PR migrates that closed set.
const _LEVEL_SYMBOL_ALLOWLIST = [
    ("src/types.jl", "warn", "DEFAULT_EXIT_SEVERITY remains Symbol until a later #104 PR"),
    ("src/config.jl", "forbid", "VALID_EXIT_SEVERITY remains Symbol until a later #104 PR"),
    ("src/config.jl", "deny", "VALID_EXIT_SEVERITY remains Symbol until a later #104 PR"),
    ("src/config.jl", "warn", "VALID_EXIT_SEVERITY remains Symbol until a later #104 PR"),
    ("src/exit_severity.jl", "warn", "exit_severity threshold ranking remains Symbol until a later #104 PR"),
    ("src/exit_severity.jl", "deny", "exit_severity threshold ranking remains Symbol until a later #104 PR"),
    ("src/exit_severity.jl", "forbid", "exit_severity threshold ranking remains Symbol until a later #104 PR"),
]

const _LEVEL_CONVERT_FNS = Set(["parse_enum", "wire_name"])

function _level_src_julia_files(dir::AbstractString)
    out = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(f, ".jl") || continue
            push!(out, joinpath(root, f))
        end
    end
    return sort(out)
end

function _level_allowlisted(rel_path::AbstractString, name::AbstractString)
    for (file, id, _) in _LEVEL_SYMBOL_ALLOWLIST
        file == rel_path && id == name && return true
    end
    return false
end

function _level_fn_name(node, src::AbstractString, pos::Int)
    k = AgentRuleLint.syntax_kind(node)
    k == AgentRuleLint.KFunction || return ""
    for (c, cp) in AgentRuleLint._child_positions(node, pos)[1]
        AgentRuleLint.syntax_is_trivia(c) && continue
        ck = AgentRuleLint.syntax_kind(c)
        if ck == AgentRuleLint.KIdentifier
            return AgentRuleLint._node_text_trim(c, src, cp)
        elseif ck == AgentRuleLint.KCall
            for (cc, ccp) in AgentRuleLint._child_positions(c, cp)[1]
                AgentRuleLint.syntax_is_trivia(cc) && continue
                AgentRuleLint.syntax_kind(cc) == AgentRuleLint.KIdentifier &&
                    return AgentRuleLint._node_text_trim(cc, src, ccp)
                break
            end
        end
        break
    end
    return ""
end

function _level_quote_ident(node, src::AbstractString, pos::Int)
    AgentRuleLint.syntax_kind(node) == AgentRuleLint.KQuote || return nothing
    for (c, p) in AgentRuleLint._child_positions(node, pos)[1]
        AgentRuleLint.syntax_is_trivia(c) && continue
        AgentRuleLint.syntax_kind(c) == AgentRuleLint.KIdentifier &&
            return AgentRuleLint._node_text_trim(c, src, p)
        AgentRuleLint.syntax_kind(c) == AgentRuleLint.KQuote &&
            return _level_quote_ident(c, src, p)
    end
    return nothing
end

function _level_snippet(src::AbstractString, pos::Int, node)
    sp = AgentRuleLint.syntax_span(node)
    stop = min(pos + sp - 1, ncodeunits(src))
    pos > stop && return ""
    return strip(String(src[pos:stop]))
end

function _walk_level_symbols!(
        node,
        pos::Int,
        src::AbstractString,
        rel::AbstractString,
        violations,
        used::Set{Tuple{String, String}},
        in_convert::Bool,
    )
    AgentRuleLint.syntax_is_trivia(node) && return
    k = AgentRuleLint.syntax_kind(node)
    string(k) == "Comment" && return
    if k == AgentRuleLint.KStringExpr || k == AgentRuleLint.KCharExpr
        AgentRuleLint._string_node_interpolated(node, pos) || return
    end

    fn = _level_fn_name(node, src, pos)
    nested_convert = in_convert || (fn in _LEVEL_CONVERT_FNS)

    if k == AgentRuleLint.KQuote && !nested_convert
        name = _level_quote_ident(node, src, pos)
        if name !== nothing && name in _LEVEL_NAMES
            line = AgentRuleLint.line_number_at_byte(src, pos)
            push!(used, (String(rel), String(name)))
            if !_level_allowlisted(rel, name)
                snippet = _level_snippet(src, pos, node)
                push!(violations, (String(rel), line, String(name), snippet))
            end
        end
    end

    for (c, cp) in AgentRuleLint._child_positions(node, pos)[1]
        _walk_level_symbols!(c, cp, src, rel, violations, used, nested_convert)
    end
    return
end

function _scan_level_symbol_source(rel::AbstractString, source::AbstractString)
    src = AgentRuleLint.normalize_source(source)
    tree = AgentRuleLint.parse_source(src; filename = rel)
    violations = Tuple{String, Int, String, String}[]
    used = Set{Tuple{String, String}}()
    _walk_level_symbols!(tree, 1, src, rel, violations, used, false)
    return violations, used
end

function collect_src_level_symbol_violations(repo_root::AbstractString)
    src = joinpath(repo_root, "src")
    violations = Tuple{String, Int, String, String}[]
    used = Set{Tuple{String, String}}()
    for path in _level_src_julia_files(src)
        rel = replace(relpath(path, repo_root), '\\' => '/')
        v, u = _scan_level_symbol_source(rel, read(path, String))
        append!(violations, v)
        union!(used, u)
    end
    return violations, used
end

@testset "src/ Level Symbol literal guard" begin
    @testset "syntax scan finds quote literals (probe sources)" begin
        v, _ = _scan_level_symbol_source(_LEVEL_PROBE_REL, "x = :forbid\n")
        @test any(x -> x[2] == 1 && x[3] == "forbid", v)
        v, _ = _scan_level_symbol_source(_LEVEL_PROBE_REL, "x == :deny\n")
        @test any(x -> x[3] == "deny", v)
        comment_only = "# :warn\n"
        v, _ = _scan_level_symbol_source(_LEVEL_PROBE_REL, comment_only)
        @test isempty(v)
        str_only = "s = \":allow\"\n"
        v, _ = _scan_level_symbol_source(_LEVEL_PROBE_REL, str_only)
        @test isempty(v)
        convert_fn = "function parse_enum(::Type{Level.T}, s::AbstractString)\n    x = :forbid\n    return x\nend\n"
        v, _ = _scan_level_symbol_source(_LEVEL_PROBE_REL, convert_fn)
        @test isempty(v)
    end

    violations, used = collect_src_level_symbol_violations(ROOT)
    for (file, line, name, snippet) in violations
        @error "Level Symbol literal outside conversion functions / allowlist" file line name snippet
    end
    @test isempty(violations)

    stale = [(f, id) for (f, id, _) in _LEVEL_SYMBOL_ALLOWLIST if (f, id) ∉ used]
    @test isempty(stale) || error(
        "allowlist entries with no use in src/: $(join(["$f:$id" for (f, id) in stale], ", "))",
    )
end
