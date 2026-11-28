const KString = JuliaSyntax.K"String"
const KChar = JuliaSyntax.K"Char"

const FOLD_MAX_DEPTH = 48
const FOLD_MAX_STEPS = 16_000

mutable struct FoldBudget
    count::Int
    limit::Int
    at_byte::Int
end

FoldBudget(limit::Int = FOLD_MAX_STEPS) = FoldBudget(0, limit, 1)

function _fold_budget!(b::FoldBudget, byte::Int = 0)
    b.count += 1
    byte > 0 && (b.at_byte = byte)
    return b.count > b.limit && throw(FoldBudgetExceeded(b.limit))
end

function _fold_budget_exceeded(err)::Bool
    return err isa FoldBudgetExceeded
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
        elseif syntax_is_trivia(c) || string(k) in ("()", "inertparen", "\"", "''")
            continue
        else
            return nothing
        end
    end
    return join(parts)
end

function _string_node_interpolated(node::GreenNode, pos::Int)
    for (c, _) in _child_positions(node, pos)[1]
        string(kind(c)) == "\$" && return true
        syntax_interpolation_child(c) && return true
    end
    return false
end

function _fold_atom(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        depth::Int,
        budget::FoldBudget,
    )::Union{Nothing, String}
    _fold_budget!(budget)
    depth > FOLD_MAX_DEPTH && return nothing
    if kind(node) == KStringExpr
        _string_node_interpolated(node, pos) && return nothing
        return _collect_string_chars(node, src, pos)
    elseif kind(node) == KCharExpr
        return _collect_string_chars(node, src, pos)
    end
    return nothing
end

function _call_callee_name(node::GreenNode, src::AbstractString, pos::Int)
    ch = children(node)
    ch === nothing && return ""
    kids, _ = _child_positions(node, pos)
    for (c, cp) in kids
        syntax_is_trivia(c) && continue
        is_leaf(c) || return ""
        return _identifier_name(c, src, cp)
    end
    return ""
end

function _fold_children_strings(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        depth::Int,
        budget::FoldBudget,
    )::Union{Nothing, Vector{String}}
    ch = children(node)
    ch === nothing && return String[]
    start = pos + span(ch[1])
    vals = String[]
    p = start
    for i in 2:length(ch)
        c = ch[i]
        if syntax_is_trivia(c)
            p += span(c)
            continue
        end
        v = try_fold_expr(c, src, p, depth + 1, budget)
        v === nothing && return nothing
        push!(vals, v.value)
        p += span(c)
    end
    return vals
end

function _fold_vect_strings(node::GreenNode, src::AbstractString, pos::Int, depth::Int, budget::FoldBudget)
    vals = String[]
    for (c, p) in _child_positions(node, pos)[1]
        syntax_is_trivia(c) && continue
        sk = string(kind(c))
        sk in ("()", ",") && continue
        v = if kind(c) == KStringExpr
            _fold_atom(c, src, p, depth + 1, budget)
        else
            folded = try_fold_expr(c, src, p, depth, budget)
            folded === nothing ? nothing : folded.value
        end
        v === nothing && return nothing
        push!(vals, v)
    end
    return vals
end

function _fold_uint8_vect(node::GreenNode, src::AbstractString, pos::Int)
    bytes = UInt8[]
    for (c, p) in _child_positions(node, pos)[1]
        string(kind(c)) in ("()", "inertparen") && continue
        kind(c) == JuliaSyntax.K"Integer" || return nothing
        n = parse(Int, strip(_node_text(src, p, c)))
        push!(bytes, UInt8(n))
    end
    return bytes
end

function _fold_uint8_ref(node::GreenNode, src::AbstractString, pos::Int)
    bytes = UInt8[]
    for (c, p) in _child_positions(node, pos)[1]
        kind(c) == JuliaSyntax.K"Integer" || continue
        n = parse(Int, strip(_node_text(src, p, c)))
        push!(bytes, UInt8(n))
    end
    return isempty(bytes) ? nothing : bytes
end

function try_fold_expr(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        depth::Int,
        budget::FoldBudget,
    )::Union{Nothing, FoldedStringExpr}
    _fold_budget!(budget)
    depth > FOLD_MAX_DEPTH && return nothing
    sp = span(node)
    byte_end = pos + sp - 1

    if syntax_is_infix_op_call(node)
        ch = children(node)
        ch === nothing && return nothing
        nargs = 0
        pos_args = Tuple{GreenNode, Int}[]
        p = pos
        for c in ch
            syntax_is_trivia(c) && (p += span(c); continue)
            push!(pos_args, (c, p))
            nargs += 1
            p += span(c)
        end
        nargs == 3 || return nothing
        (left, lp), (op, oppos), (right, rp) = pos_args
        opname = _identifier_name(op, src, oppos)
        opname == "*" || return nothing
        l = try_fold_expr(left, src, lp, depth + 1, budget)
        r = try_fold_expr(right, src, rp, depth + 1, budget)
        (l === nothing || r === nothing) && return nothing
        val = l.value * r.value
        return FoldedStringExpr(val, pos, byte_end)
    end

    if kind(node) == KStringExpr || kind(node) == KCharExpr
        v = _fold_atom(node, src, pos, depth, budget)
        v === nothing && return nothing
        return FoldedStringExpr(v, pos, byte_end)
    end

    if kind(node) == KCall
        fname = _call_callee_name(node, src, pos)
        if fname == "string"
            parts = _fold_children_strings(node, src, pos, depth, budget)
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
                (string(k) in ("()", "inertparen", ",") || syntax_is_trivia(c)) && (p += span(c); continue)
                push!(args, c)
                push!(argpos, p)
                p += span(c)
            end
            length(args) < 2 && return nothing
            arr = args[1]
            kind(arr) == KVect || return nothing
            strings = _fold_vect_strings(arr, src, argpos[1], depth, budget)
            strings === nothing && return nothing
            delim = try_fold_expr(args[2], src, argpos[2], depth + 1, budget)
            delim === nothing && return nothing
            if length(args) == 2
                val = join(strings, delim.value)
            else
                last_d = try_fold_expr(args[3], src, argpos[3], depth + 1, budget)
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
                (string(k) in ("()", "inertparen", ",") || syntax_is_trivia(c)) && (p += span(c); continue)
                push!(args, c)
                push!(argpos, p)
                p += span(c)
            end
            length(args) < 2 && return nothing
            op = args[1]
            opname = _identifier_name(op, src, argpos[1])
            opname == "*" || return nothing
            coll = args[2]
            kind(coll) == KVect || return nothing
            strings = _fold_vect_strings(coll, src, argpos[2], depth, budget)
            strings === nothing && return nothing
            val = join(strings)
            return FoldedStringExpr(val, pos, byte_end)
        elseif fname == "String"
            arg = nothing
            argp = 0
            for (c, p) in _child_positions(node, pos)[1]
                if kind(c) == KRef || kind(c) == KVect
                    arg = c
                    argp = p
                    break
                end
            end
            arg === nothing && return nothing
            bytes =
                kind(arg) == KVect ?
                _fold_uint8_vect(arg, src, argp) :
                _fold_uint8_ref(arg, src, argp)
            bytes === nothing && return nothing
            return FoldedStringExpr(String(bytes), pos, byte_end)
        end
    end

    if kind(node) == KVect
        strings = _fold_vect_strings(node, src, pos, depth, budget)
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
        budget::FoldBudget,
        out::Vector{FoldedStringExpr},
    )
    _fold_budget!(budget, pos)
    folded = try_fold_expr(node, src, pos, depth, budget)
    if folded !== nothing
        push!(out, folded)
    end
    for (c, p) in _child_positions(node, pos)[1]
        syntax_is_trivia(c) && continue
        _walk_collect_folds(c, src, p, depth + 1, budget, out)
    end
    return
end

function collect_folded_string_exprs(
        tree::GreenNode,
        source::AbstractString;
        max_steps::Int = FOLD_MAX_STEPS,
    )::FoldCollectResult
    src = normalize_source(source)
    budget = FoldBudget(max_steps)
    out = FoldedStringExpr[]
    try
        _walk_collect_folds(tree, src, 1, 0, budget, out)
    catch err
        if _fold_budget_exceeded(err)
            return FoldCollectResult(out, true, budget.at_byte)
        elseif err isa InterruptException
            rethrow()
        else
            throw(err)
        end
    end
    return FoldCollectResult(out, false, budget.at_byte)
end

function folded_string_literals(tree::GreenNode, source::AbstractString)
    return [f.value for f in collect_folded_string_exprs(tree, source).folds]
end

function fold_expr(node::GreenNode, source::AbstractString; byte_offset::Int = 1, depth::Int = 0)
    budget = FoldBudget()
    return try_fold_expr(node, normalize_source(source), byte_offset, depth, budget)
end
