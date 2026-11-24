using JuliaSyntax: GreenNode, span, children, head, kind, is_leaf, is_infix_op_call
const KString = JuliaSyntax.K"String"
const KChar = JuliaSyntax.K"Char"

const FOLD_MAX_DEPTH = 48
const FOLD_MAX_STEPS = 16_000
const FOLD_BUDGET_MSG = "constant fold step budget exceeded"
const _ACTIVE_FOLD_LIMIT = Ref(FOLD_MAX_STEPS)

function _fold_budget!(n::Ref{Int})
    n[] += 1
    return n[] > _ACTIVE_FOLD_LIMIT[] && throw(ArgumentError(FOLD_BUDGET_MSG))
end

function _fold_budget_exceeded(err)::Bool
    return err isa ArgumentError && err.msg == FOLD_BUDGET_MSG
end

function _align_byte_index(src::AbstractString, i::Int)
    n = ncodeunits(src)
    i = max(1, min(i, n))
    while i ≤ n && !isvalid(src, i)
        i += 1
    end
    while i > 1 && !isvalid(src, i)
        i -= 1
    end
    return i
end

function _node_text(src::AbstractString, pos::Int, node::GreenNode)
    sp = span(node)
    n = ncodeunits(src)
    pos = _align_byte_index(src, pos)
    stop = _align_byte_index(src, min(pos + sp - 1, n))
    return pos > stop ? "" : src[pos:stop]
end

function _child_positions(node::GreenNode, start_pos::Int)
    ch = children(node)
    ch === nothing && return Tuple{GreenNode, Int}[], start_pos + span(node)
    pos = start_pos
    out = Tuple{GreenNode, Int}[]
    for c in ch
        push!(out, (c, pos))
        pos += span(c)
    end
    return out, pos
end

function _identifier_name(node::GreenNode, src::AbstractString, pos::Int)
    txt = strip(_node_text(src, pos, node))
    return txt
end

function _collect_string_chars(node::GreenNode, src::AbstractString, pos::Int)
    parts = String[]
    for (c, p) in _child_positions(node, pos)[1]
        k = kind(c)
        if k == KString
            push!(parts, _node_text(src, p, c))
        elseif JuliaSyntax.is_trivia(head(c)) || string(k) in ("()", "inertparen", "\"", "''")
            continue
        else
            return nothing
        end
    end
    return join(parts)
end

function _string_node_interpolated(node::GreenNode, src::AbstractString, pos::Int)
    for (c, _) in _child_positions(node, pos)[1]
        k = kind(c)
        string(kind(c)) == "\$" && return true
        summary(c) == "interpolation" && return true
    end
    return false
end

function _fold_atom(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        depth::Int,
        steps::Ref{Int},
    )::Union{Nothing, String}
    _fold_budget!(steps)
    depth > FOLD_MAX_DEPTH && return nothing
    if summary(node) == "string"
        _string_node_interpolated(node, src, pos) && return nothing
        return _collect_string_chars(node, src, pos)
    elseif summary(node) == "char"
        return _collect_string_chars(node, src, pos)
    end
    return nothing
end

function _call_callee_name(node::GreenNode, src::AbstractString, pos::Int)
    ch = children(node)
    ch === nothing && return ""
    c = ch[1]
    is_leaf(c) || return ""
    return _identifier_name(c, src, pos + 1)
end

function _fold_children_strings(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        depth::Int,
        steps::Ref{Int},
    )::Union{Nothing, Vector{String}}
    ch = children(node)
    ch === nothing && return String[]
    start = pos + span(ch[1])
    vals = String[]
    p = start
    for i in 2:length(ch)
        c = ch[i]
        k = kind(c)
        if JuliaSyntax.is_trivia(head(c))
            p += span(c)
            continue
        end
        v = try_fold_expr(c, src, p, depth + 1, steps)
        v === nothing && return nothing
        push!(vals, v.value)
        p += span(c)
    end
    return vals
end

function _fold_vect_strings(node::GreenNode, src::AbstractString, pos::Int, depth::Int, steps::Ref{Int})
    vals = String[]
    for (c, p) in _child_positions(node, pos)[1]
        JuliaSyntax.is_trivia(head(c)) && continue
        summary(c) == "string" || return nothing
        v = _fold_atom(c, src, p, depth + 1, steps)
        v === nothing && return nothing
        push!(vals, v)
    end
    return vals
end

function _fold_uint8_vect(node::GreenNode, src::AbstractString, pos::Int)
    bytes = UInt8[]
    for (c, p) in _child_positions(node, pos)[1]
        k = kind(c)
        string(kind(c)) in ("()", "inertparen") && continue
        kind(c) == JuliaSyntax.K"Integer" || return nothing
        n = parse(Int, strip(_node_text(src, p, c)))
        push!(bytes, UInt8(n))
    end
    return bytes
end

function try_fold_expr(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        depth::Int,
        steps::Ref{Int},
    )::Union{Nothing, FoldedStringExpr}
    _fold_budget!(steps)
    depth > FOLD_MAX_DEPTH && return nothing
    sp = span(node)
    byte_end = pos + sp - 1

    if is_infix_op_call(head(node))
        ch = children(node)
        ch === nothing && return nothing
        nargs = 0
        pos_args = Tuple{GreenNode, Int}[]
        p = pos
        for c in ch
            JuliaSyntax.is_trivia(head(c)) && (p += span(c); continue)
            push!(pos_args, (c, p))
            nargs += 1
            p += span(c)
        end
        nargs == 3 || return nothing
        (left, lp), (op, oppos), (right, rp) = pos_args
        opname = _identifier_name(op, src, oppos)
        opname == "*" || return nothing
        l = try_fold_expr(left, src, lp, depth + 1, steps)
        r = try_fold_expr(right, src, rp, depth + 1, steps)
        (l === nothing || r === nothing) && return nothing
        val = l.value * r.value
        return FoldedStringExpr(val, pos, byte_end)
    end

    if summary(node) == "string" || summary(node) == "char"
        v = _fold_atom(node, src, pos, depth, steps)
        v === nothing && return nothing
        return FoldedStringExpr(v, pos, byte_end)
    end

    if summary(node) == "call"
        fname = _call_callee_name(node, src, pos)
        if fname == "string"
            parts = _fold_children_strings(node, src, pos, depth, steps)
            parts === nothing && return nothing
            return FoldedStringExpr(join(parts), pos, byte_end)
        elseif fname == "join"
            ch = children(node)
            ch === nothing && return nothing
            if length(ch) < 3
                return nothing
            end
            p = pos + span(ch[1]) + 1
            # skip '('
            args = GreenNode[]
            argpos = Int[]
            for i in 2:length(ch)
                c = ch[i]
                k = kind(c)
                (string(k) in ("()", "inertparen", ",") || JuliaSyntax.is_trivia(head(c))) && (p += span(c); continue)
                push!(args, c)
                push!(argpos, p)
                p += span(c)
            end
            length(args) < 2 && return nothing
            arr = args[1]
            summary(arr) == "vect" || return nothing
            strings = _fold_vect_strings(arr, src, argpos[1], depth, steps)
            strings === nothing && return nothing
            delim = try_fold_expr(args[2], src, argpos[2], depth + 1, steps)
            delim === nothing && return nothing
            if length(args) == 2
                val = join(strings, delim.value)
            else
                last_d = try_fold_expr(args[3], src, argpos[3], depth + 1, steps)
                last_d === nothing && return nothing
                length(strings) >= 1 || return nothing
                val = join(strings[1:(end - 1)], delim.value) * last_d.value * strings[end]
            end
            return FoldedStringExpr(val, pos, byte_end)
        elseif fname == "reduce"
            ch = children(node)
            ch === nothing && return nothing
            args = GreenNode[]
            argpos = Int[]
            p = pos + span(ch[1])
            for i in 2:length(ch)
                c = ch[i]
                k = kind(c)
                (string(k) in ("()", "inertparen", ",") || JuliaSyntax.is_trivia(head(c))) && (p += span(c); continue)
                push!(args, c)
                push!(argpos, p)
                p += span(c)
            end
            length(args) < 2 && return nothing
            op = args[1]
            opname = _identifier_name(op, src, argpos[1])
            opname == "*" || return nothing
            coll = args[2]
            summary(coll) == "vect" || return nothing
            strings = _fold_vect_strings(coll, src, argpos[2], depth, steps)
            strings === nothing && return nothing
            val = join(strings)
            return FoldedStringExpr(val, pos, byte_end)
        elseif fname == "String"
            ch = children(node)
            ch === nothing || length(ch) < 3 && return nothing
            arg = nothing
            argp = 0
            p = pos
            for c in children(node)
                p += span(c)
                if summary(c) == "ref" || summary(c) == "vect"
                    arg = c
                    argp = p - span(c)
                    break
                end
            end
            arg === nothing && return nothing
            if summary(arg) == "vect"
                bytes = _fold_uint8_vect(arg, src, argp)
                bytes === nothing && return nothing
                return FoldedStringExpr(String(bytes), pos, byte_end)
            end
        end
    end

    if summary(node) == "vect"
        strings = _fold_vect_strings(node, src, pos, depth, steps)
        strings === nothing && return nothing
        return FoldedStringExpr(join(strings), pos, byte_end)
    end

    return nothing
end

function _walk_collect_folds(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        depth::Int,
        steps::Ref{Int},
        out::Vector{FoldedStringExpr},
    )
    _fold_budget!(steps)
    summary(node) == "toplevel" || summary(node) == "=" || true
    folded = try_fold_expr(node, src, pos, depth, steps)
    if folded !== nothing
        push!(out, folded)
    end
    for (c, p) in _child_positions(node, pos)[1]
        JuliaSyntax.is_trivia(head(c)) && continue
        _walk_collect_folds(c, src, p, depth + 1, steps, out)
    end
    return
end

function collect_folded_string_exprs(
        tree::GreenNode,
        source::AbstractString;
        max_steps::Int = FOLD_MAX_STEPS,
    )::Vector{FoldedStringExpr}
    src = normalize_source(source)
    steps = Ref(0)
    out = FoldedStringExpr[]
    prev_limit = _ACTIVE_FOLD_LIMIT[]
    _ACTIVE_FOLD_LIMIT[] = max_steps
    try
        _walk_collect_folds(tree, src, 1, 0, steps, out)
    catch err
        if _fold_budget_exceeded(err)
            return out
        elseif err isa InterruptException
            rethrow()
        else
            throw(err)
        end
    finally
        _ACTIVE_FOLD_LIMIT[] = prev_limit
    end
    return out
end

function folded_string_literals(tree::GreenNode, source::AbstractString)
    return [f.value for f in collect_folded_string_exprs(tree, source)]
end

function fold_expr(node::GreenNode, source::AbstractString; byte_offset::Int = 1, depth::Int = 0)
    steps = Ref(0)
    return try_fold_expr(node, normalize_source(source), byte_offset, depth, steps)
end
