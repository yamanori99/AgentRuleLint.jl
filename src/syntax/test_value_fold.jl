# Static value folding for @test conditions (no eval). Extends string folding only where needed.

const _FOLD_TEST_MAX_DEPTH = 32

FoldedTestValue = Union{Bool, Int, Float64, String}

function _fold_test_budget!(steps::Ref{Int})
    steps[] += 1
    return steps[] > FOLD_MAX_STEPS && throw(ArgumentError(FOLD_BUDGET_MSG))
end

function _node_text_trim(node::GreenNode, src::AbstractString, pos::Int)
    return strip(_node_text(src, pos, node))
end

function _parse_bool_text(txt::AbstractString)
    t = strip(txt)
    t == "true" && return true
    t == "false" && return false
    return nothing
end

function _parse_int_node(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "Integer" || return nothing
    txt = _node_text_trim(node, src, pos)
    m = match(r"^-?\d+$", txt)
    m === nothing && return nothing
    return parse(Int, txt)
end

function _parse_float_node(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "Float" || return nothing
    txt = _node_text_trim(node, src, pos)
    try
        return parse(Float64, txt)
    catch
        return nothing
    end
end

function _is_eq_op(node::GreenNode, src::AbstractString, pos::Int)
    return summary(node) == "Identifier" && _node_text_trim(node, src, pos) == "=="
end

function _try_fold_test_value(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        depth::Int,
        steps::Ref{Int},
        consts::Dict{String, FoldedTestValue},
    )::Union{Nothing, FoldedTestValue}
    _fold_test_budget!(steps)
    depth > _FOLD_TEST_MAX_DEPTH && return nothing

    s = summary(node)
    if s == "Bool" || (is_leaf(node) && kind(node) == JuliaSyntax.K"Bool")
        b = _parse_bool_text(_node_text_trim(node, src, pos))
        return b
    elseif s == "Integer"
        return _parse_int_node(node, src, pos)
    elseif s == "Float"
        return _parse_float_node(node, src, pos)
    elseif s == "string" || s == "char"
        v = _fold_atom(node, src, pos, depth, steps)
        return v
    elseif s == "Identifier"
        name = _node_text_trim(node, src, pos)
        return get(consts, name, nothing)
    end

    if s == "call"
        kids, _ = _child_positions(node, pos)
        args = Tuple{GreenNode, Int}[]
        for (c, cp) in kids
            JuliaSyntax.is_trivia(head(c)) && continue
            push!(args, (c, cp))
        end
        length(args) == 3 || return nothing
        (left, lp), (op, oppos), (right, rp) = args
        _is_eq_op(op, src, oppos) || return nothing
        l = _try_fold_test_value(left, src, lp, depth + 1, steps, consts)
        r = _try_fold_test_value(right, src, rp, depth + 1, steps, consts)
        l === nothing && r === nothing && return nothing
        l === r && return true
        if l isa String && r isa String
            return l == r
        elseif l isa Int && r isa Int
            return l == r
        elseif l isa Float64 && r isa Float64
            return l == r
        elseif l isa Bool && r isa Bool
            return l == r
        end
        return false
    end

    if is_infix_op_call(head(node))
        kids, _ = _child_positions(node, pos)
        args = Tuple{GreenNode, Int}[]
        for (c, cp) in kids
            JuliaSyntax.is_trivia(head(c)) && continue
            push!(args, (c, cp))
        end
        length(args) == 3 || return nothing
        (left, lp), (op, oppos), (right, rp) = args
        _is_eq_op(op, src, oppos) || return nothing
        l = _try_fold_test_value(left, src, lp, depth + 1, steps, consts)
        r = _try_fold_test_value(right, src, rp, depth + 1, steps, consts)
        (l === nothing || r === nothing) && return nothing
        return l == r
    end

    return nothing
end

function test_condition_folds_true(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        consts::Dict{String, FoldedTestValue},
    )::Bool
    steps = Ref(0)
    try
        v = _try_fold_test_value(node, src, pos, 0, steps, consts)
        return v === true
    catch err
        if _fold_budget_exceeded(err)
            return false
        end
        rethrow()
    end
end

function collect_toplevel_const_bindings(
        tree::GreenNode,
        src::AbstractString,
    )::Dict{String, FoldedTestValue}
    consts = Dict{String, FoldedTestValue}()
    steps = Ref(0)
    for (node, pos) in _toplevel_stmt_nodes(tree)
        summary(node) == "const" || continue
        bind = _const_binding_pair(node, src, pos)
        bind === nothing && continue
        name, val_node, val_pos = bind
        v = try
            _try_fold_test_value(val_node, src, val_pos, 0, steps, consts)
        catch err
            if _fold_budget_exceeded(err)
                nothing
            else
                rethrow()
            end
        end
        v === nothing && continue
        consts[name] = v
    end
    return consts
end

function _toplevel_stmt_nodes(tree::GreenNode)
    out = Tuple{GreenNode, Int}[]
    summary(tree) == "toplevel" || return out
    for (c, p) in _child_positions(tree, 1)[1]
        JuliaSyntax.is_trivia(head(c)) && continue
        push!(out, (c, p))
    end
    return out
end

function _const_binding_pair(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "const" || return nothing
    for (c, cp) in _child_positions(node, pos)[1]
        summary(c) == "=" || continue
        left = nothing
        right = nothing
        lp = 0
        rp = 0
        for (cc, cpp) in _child_positions(c, cp)[1]
            JuliaSyntax.is_trivia(head(cc)) && continue
            if left === nothing
                left = cc
                lp = cpp
            else
                right = cc
                rp = cpp
                break
            end
        end
        left === nothing && return nothing
        right === nothing && return nothing
        summary(left) == "Identifier" || return nothing
        name = _node_text_trim(left, src, lp)
        return (name, right, rp)
    end
    return nothing
end
