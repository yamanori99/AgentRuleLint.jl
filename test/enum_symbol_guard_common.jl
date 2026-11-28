module EnumSymbolGuard

using AgentRuleLint

const _ENUM_SYMBOL_CONVERT_FNS = Set(["parse_enum", "wire_name"])

function _enum_symbol_src_julia_files(dir::AbstractString)
    out = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(f, ".jl") || continue
            push!(out, joinpath(root, f))
        end
    end
    return sort(out)
end

function _enum_symbol_allowlisted(
        allowlist::Vector{Tuple{String, String, String}},
        rel_path::AbstractString,
        name::AbstractString,
    )
    for (file, id, _) in allowlist
        file == rel_path && id == name && return true
    end
    return false
end

function _enum_symbol_fn_name(node, src::AbstractString, pos::Int)
    ARL = AgentRuleLint
    k = ARL.syntax_kind(node)
    k == ARL.KFunction || return ""
    for (c, cp) in ARL._child_positions(node, pos)[1]
        ARL.syntax_is_trivia(c) && continue
        ck = ARL.syntax_kind(c)
        if ck == ARL.KIdentifier
            return ARL._node_text_trim(c, src, cp)
        elseif ck == ARL.KCall
            for (cc, ccp) in ARL._child_positions(c, cp)[1]
                ARL.syntax_is_trivia(cc) && continue
                ARL.syntax_kind(cc) == ARL.KIdentifier && return ARL._node_text_trim(cc, src, ccp)
                break
            end
        end
        break
    end
    return ""
end

function _enum_symbol_quote_ident(node, src::AbstractString, pos::Int)
    ARL = AgentRuleLint
    ARL.syntax_kind(node) == ARL.KQuote || return nothing
    for (c, p) in ARL._child_positions(node, pos)[1]
        ARL.syntax_is_trivia(c) && continue
        ARL.syntax_kind(c) == ARL.KIdentifier && return ARL._node_text_trim(c, src, p)
        ARL.syntax_kind(c) == ARL.KQuote && return _enum_symbol_quote_ident(c, src, p)
    end
    return nothing
end

function _enum_symbol_snippet(src::AbstractString, pos::Int, node)
    ARL = AgentRuleLint
    sp = ARL.syntax_span(node)
    stop = min(pos + sp - 1, ncodeunits(src))
    pos > stop && return ""
    return strip(String(src[pos:stop]))
end

function _walk_enum_symbols!(
        node,
        pos::Int,
        src::AbstractString,
        rel::AbstractString,
        names::Set{String},
        allowlist::Vector{Tuple{String, String, String}},
        violations,
        used::Set{Tuple{String, String}},
        in_convert::Bool,
    )
    ARL = AgentRuleLint
    ARL.syntax_is_trivia(node) && return
    k = ARL.syntax_kind(node)
    string(k) == "Comment" && return
    if k == ARL.KStringExpr || k == ARL.KCharExpr
        ARL._string_node_interpolated(node, pos) || return
    end

    fn = _enum_symbol_fn_name(node, src, pos)
    nested_convert = in_convert || (fn in _ENUM_SYMBOL_CONVERT_FNS)

    if k == ARL.KQuote && !nested_convert
        name = _enum_symbol_quote_ident(node, src, pos)
        if name !== nothing && name in names
            line = ARL.line_number_at_byte(src, pos)
            push!(used, (String(rel), String(name)))
            if !_enum_symbol_allowlisted(allowlist, rel, name)
                snippet = _enum_symbol_snippet(src, pos, node)
                push!(violations, (String(rel), line, String(name), snippet))
            end
        end
    end

    for (c, cp) in ARL._child_positions(node, pos)[1]
        _walk_enum_symbols!(
            c,
            cp,
            src,
            rel,
            names,
            allowlist,
            violations,
            used,
            nested_convert,
        )
    end
    return
end

export scan_enum_symbol_source, collect_src_enum_symbol_violations

function scan_enum_symbol_source(
        rel::AbstractString,
        source::AbstractString,
        names::Set{String},
        allowlist::Vector{Tuple{String, String, String}},
    )
    ARL = AgentRuleLint
    src = ARL.normalize_source(source)
    tree = ARL.parse_source(src; filename = rel)
    violations = Tuple{String, Int, String, String}[]
    used = Set{Tuple{String, String}}()
    _walk_enum_symbols!(tree, 1, src, rel, names, allowlist, violations, used, false)
    return violations, used
end

function collect_src_enum_symbol_violations(
        repo_root::AbstractString,
        names::Set{String},
        allowlist::Vector{Tuple{String, String, String}},
    )
    src = joinpath(repo_root, "src")
    violations = Tuple{String, Int, String, String}[]
    used = Set{Tuple{String, String}}()
    for path in _enum_symbol_src_julia_files(src)
        rel = replace(relpath(path, repo_root), '\\' => '/')
        v, u = scan_enum_symbol_source(rel, read(path, String), names, allowlist)
        append!(violations, v)
        union!(used, u)
    end
    return violations, used
end

end # module
