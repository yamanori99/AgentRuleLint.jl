const _CMD_WRAPPER_CALLEES = Set(["run", "open", "read", "pipeline", "Cmd"])

"""True for `Cmd` or a dotted constructor whose leaf is `Cmd` (e.g. `Base.Cmd`)."""
function _is_cmd_constructor(fname::AbstractString)
    return fname == "Cmd" || endswith(fname, ".Cmd")
end

function _cmdstring_text(node::GreenNode, src::AbstractString, pos::Int)
    kind(node) == KCmdstring || return nothing
    hasinterp = false
    parts = String[]
    for (c, p) in _child_positions(node, pos)[1]
        if kind(c) == KCmdString
            push!(parts, _node_text(src, p, c))
        elseif syntax_interpolation_child(c)
            hasinterp = true
        end
    end
    hasinterp && return nothing
    text = join(parts)
    return FoldedStringExpr(text, pos, pos + span(node) - 1)
end

function _collect_cmd_from_vect(node::GreenNode, src::AbstractString, pos::Int, depth::Int, budget::FoldBudget)
    kind(node) == KVect || return String[]
    strings = _fold_vect_strings(node, src, pos, depth, budget)
    return strings === nothing ? String[] : strings
end

function _collect_cmd_from_call(node::GreenNode, src::AbstractString, pos::Int, budget::FoldBudget)
    fname, args, argpos = _shell_call_parts(node, src, pos)
    _is_cmd_constructor(fname) || return FoldedStringExpr[]
    out = FoldedStringExpr[]
    for (arg, ap) in zip(args, argpos)
        if kind(arg) == KVect
            strings = _collect_cmd_from_vect(arg, src, ap, 0, budget)
            isempty(strings) && continue
            val = join(strings, " ")
            push!(out, FoldedStringExpr(val, ap, ap + syntax_span(arg) - 1))
        elseif kind(arg) == KStringExpr || kind(arg) == KCmdstring
            folded = try_fold_expr(arg, src, ap, 0, budget)
            folded !== nothing && push!(out, folded)
        end
    end
    return out
end

function _shell_call_parts(node::GreenNode, src::AbstractString, pos::Int)
    kind(node) == KCall || return ("", GreenNode[], Int[])
    syntax_is_infix_op_call(node) && return ("", GreenNode[], Int[])
    fname = ""
    args = GreenNode[]
    argpos = Int[]
    for (c, p) in _child_positions(node, pos)[1]
        syntax_is_trivia(c) && continue
        if isempty(fname)
            if kind(c) == KDot
                fname = _shell_dot_callee(c, src, p)
            elseif syntax_is_leaf(c)
                fname = _identifier_name(c, src, p)
            else
                return ("", GreenNode[], Int[])
            end
        else
            sk = string(kind(c))
            sk in ("()", "inertparen", ",") && continue
            push!(args, c)
            push!(argpos, p)
        end
    end
    return (fname, args, argpos)
end

function _shell_dot_callee(node::GreenNode, src::AbstractString, pos::Int)
    kind(node) == KDot || return ""
    parts = String[]
    for (cc, cpp) in _child_positions(node, pos)[1]
        syntax_is_leaf(cc) && push!(parts, _identifier_name(cc, src, cpp))
    end
    isempty(parts) && return ""
    txt = join(parts, ".")
    occursin("...", txt) && length(parts) >= 2 && return parts[1] * "." * parts[end]
    return txt
end

function _walk_cmd_strings!(
        node::GreenNode,
        src::AbstractString,
        pos::Int,
        budget::FoldBudget,
        out::Vector{FoldedStringExpr},
    )
    if kind(node) == KCmdstring
        cs = _cmdstring_text(node, src, pos)
        cs !== nothing && push!(out, cs)
    elseif kind(node) == KCall
        fname, args, argpos = _shell_call_parts(node, src, pos)
        if _is_cmd_constructor(fname)
            append!(out, _collect_cmd_from_call(node, src, pos, budget))
        elseif fname in _CMD_WRAPPER_CALLEES
            for (arg, ap) in zip(args, argpos)
                if kind(arg) == KCmdstring
                    cs = _cmdstring_text(arg, src, ap)
                    cs !== nothing && push!(out, cs)
                elseif kind(arg) == KCall
                    afname, _, _ = _shell_call_parts(arg, src, ap)
                    _is_cmd_constructor(afname) &&
                        append!(out, _collect_cmd_from_call(arg, src, ap, budget))
                end
            end
        end
    end
    for (c, p) in _child_positions(node, pos)[1]
        syntax_is_trivia(c) && continue
        _walk_cmd_strings!(c, src, p, budget, out)
    end
    return nothing
end

"""
    collect_cmd_string_literals(tree, source) -> FoldCollectResult

Statically recover shell/Cmd text from backtick cmdstrings, `Cmd([...])` /
`Base.Cmd([...])`, and `pipeline` argument trees. Reuses `try_fold_expr` for string
concatenation and `String(UInt8[...])` forms.

**Limits (fail-closed static analysis):**
- Dynamic `Cmd` sources, non-literal `run`/`open`/`read`/`pipeline` operands, and
  commands built from runtime variables are invisible.
- Cmd interpolation (`\$(...)`) and string interpolation cancel folding for that
  fragment.
- Step budget matches `collect_folded_string_exprs` (`FOLD_MAX_STEPS`). Budget
  exhaustion sets `budget_exceeded` rather than throwing (callers emit a diagnostic).
"""
function collect_cmd_string_literals(
        tree::GreenNode,
        source::AbstractString;
        max_steps::Int = FOLD_MAX_STEPS,
    )::FoldCollectResult
    src = normalize_source(source)
    budget = FoldBudget(max_steps)
    out = FoldedStringExpr[]
    try
        _walk_cmd_strings!(tree, src, 1, budget, out)
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
