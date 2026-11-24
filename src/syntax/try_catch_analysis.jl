using JuliaSyntax: GreenNode, children, head, kind, span, summary

const _STMT_TRIVIA = ("NewlineWs", "SemicolonWs")

struct TryCatchSite
    try_pos::Int
    try_line::Int
    catch_var::Union{Nothing, Symbol}
    catch_body::Union{Nothing, GreenNode}
    catch_body_pos::Int
end

function _catch_binding_name(node::GreenNode, src::AbstractString, pos::Int)
    s = summary(node)
    if s == "Placeholder"
        return :anonymous
    elseif s == "Identifier"
        nm = _identifier_name(node, src, pos)
        isempty(nm) && return :anonymous
        return Symbol(nm)
    end
    return nothing
end

function _try_catch_site(node::GreenNode, pos::Int, src::AbstractString)::Union{Nothing, TryCatchSite}
    summary(node) == "try" || return nothing
    catch_node = nothing
    catch_pos = 0
    for (c, p) in _child_positions(node, pos)[1]
        if summary(c) == "catch"
            catch_node = c
            catch_pos = p
        end
    end
    catch_node === nothing && return nothing
    catch_var = nothing
    catch_body = nothing
    catch_body_pos = 0
    for (c, p) in _child_positions(catch_node, catch_pos)[1]
        s = summary(c)
        if s == "Identifier" || s == "Placeholder"
            catch_var = _catch_binding_name(c, src, p)
        elseif s == "block"
            catch_body = c
            catch_body_pos = p
        end
    end
    catch_body === nothing && return nothing
    try_line = line_number_at_byte(src, pos)
    return TryCatchSite(pos, try_line, catch_var, catch_body, catch_body_pos)
end

function _collect_try_catch_sites(node::GreenNode, pos::Int, src::AbstractString, out::Vector{TryCatchSite})
    site = _try_catch_site(node, pos, src)
    site !== nothing && push!(out, site)
    for (c, p) in _child_positions(node, pos)[1]
        _collect_try_catch_sites(c, p, src, out)
    end
    return nothing
end

function collect_try_catch_sites(tree::GreenNode, src::AbstractString)
    out = TryCatchSite[]
    _collect_try_catch_sites(tree, 1, normalize_source(src), out)
    return out
end

function _block_statements(block::GreenNode, pos::Int)
    out = Tuple{GreenNode, Int}[]
    for (c, p) in _child_positions(block, pos)[1]
        summary(c) in _STMT_TRIVIA && continue
        push!(out, (c, p))
    end
    return out
end

function _callee_name(node::GreenNode, pos::Int, src::AbstractString)
    summary(node) != "call" && return ""
    for (c, _) in _child_positions(node, pos)[1]
        summary(c) == "Identifier" && return _identifier_name(c, src, pos)
    end
    return ""
end

function _is_rethrow_or_throw(node::GreenNode, pos::Int, src::AbstractString)
    nm = _callee_name(node, pos, src)
    return nm == "rethrow" || nm == "throw"
end

function _propagating_call(node::GreenNode, pos::Int, src::AbstractString)
    return _is_rethrow_or_throw(node, pos, src)
end

function _shortcircuit_rhs_propagates(node::GreenNode, pos::Int, src::AbstractString, op::String)
    s = summary(node)
    s == op || return false
    saw_op = false
    for (c, p) in _child_positions(node, pos)[1]
        summary(c) == op && (saw_op = true)
        if saw_op && !JuliaSyntax.is_trivia(head(c))
            return _expr_always_propagates(c, p, src)
        end
    end
    return false
end

function _or_chain_propagates(node::GreenNode, pos::Int, src::AbstractString)
    return _shortcircuit_rhs_propagates(node, pos, src, "||")
end

function _and_chain_propagates(node::GreenNode, pos::Int, src::AbstractString)
    return _shortcircuit_rhs_propagates(node, pos, src, "&&")
end

function _macro_is_warn(node::GreenNode, pos::Int, src::AbstractString)
    summary(node) != "macrocall" && return false
    txt = _node_text(src, pos, node)
    return occursin(r"@warn\b", txt)
end

function _macro_warn_has_exception_kw(node::GreenNode, pos::Int, src::AbstractString)
    _macro_is_warn(node, pos, src) || return false
    for (c, cp) in _child_positions(node, pos)[1]
        summary(c) == "=" || continue
        txt = _node_text(src, cp, c)
        return occursin(r"\bexception\s*=", txt)
    end
    return false
end

function _stmt_fail_closed_return(node::GreenNode, pos::Int, src::AbstractString)
    summary(node) != "return" && return false
    for (c, p) in _child_positions(node, pos)[1]
        summary(c) == "call" || continue
        nm = _callee_name(c, p, src)
        return nm == "_emit_fail_closed"
    end
    return false
end

function _stmt_is_warn_only(node::GreenNode, pos::Int, src::AbstractString; warn_counts::Bool)
    if _macro_warn_has_exception_kw(node, pos, src)
        return !warn_counts
    end
    if _macro_is_warn(node, pos, src)
        return !warn_counts
    end
    return false
end

function _else_block_after_else_keyword(node::GreenNode, pos::Int)
    pending = false
    for (c, p) in _child_positions(node, pos)[1]
        s = summary(c)
        if s == "else"
            pending = true
            continue
        end
        if pending && s == "block"
            return c, p
        end
        pending = false
    end
    return nothing, 0
end

function _is_elseif_clause(node::GreenNode)
    summary(node) != "elseif" && return false
    ch = children(node)
    return ch !== nothing && length(ch) > 1
end

function _elseif_chain_final_else(elseif_node::GreenNode, pos::Int)
    for (c, p) in _child_positions(elseif_node, pos)[1]
        _is_elseif_clause(c) || continue
        return _elseif_chain_final_else(c, p)
    end
    return _else_block_after_else_keyword(elseif_node, pos)
end

function _if_final_else_block(node::GreenNode, pos::Int)
    summary(node) != "if" && return nothing, 0
    for (c, p) in _child_positions(node, pos)[1]
        _is_elseif_clause(c) || continue
        return _elseif_chain_final_else(c, p)
    end
    return _else_block_after_else_keyword(node, pos)
end

function _if_else_propagates(node::GreenNode, pos::Int, src::AbstractString)
    else_block, else_pos = _if_final_else_block(node, pos)
    else_block === nothing && return false
    for (st, sp) in _block_statements(else_block, else_pos)
        _expr_always_propagates(st, sp, src) && return true
    end
    return false
end

function _expr_always_propagates(node::GreenNode, pos::Int, src::AbstractString)
    s = summary(node)
    if s == "call"
        return _propagating_call(node, pos, src)
    elseif s == "||"
        return _or_chain_propagates(node, pos, src)
    elseif s == "&&"
        return _and_chain_propagates(node, pos, src)
    elseif s == "if"
        return _if_else_propagates(node, pos, src)
    end
    return false
end

function _if_without_else(node::GreenNode, pos::Int)
    summary(node) != "if" && return false
    return _if_final_else_block(node, pos)[1] === nothing
end

function _stmt_acceptable_warn_handling(node::GreenNode, pos::Int, src::AbstractString; warn_counts::Bool)
    return warn_counts && _macro_warn_has_exception_kw(node, pos, src)
end

function _catch_body_swallows(body::GreenNode, pos::Int, src::AbstractString; warn_counts_as_handling::Bool)
    stmts = _block_statements(body, pos)
    isempty(stmts) && return true
    any_non_handling = false
    for (i, (stmt, sp)) in enumerate(stmts)
        _expr_always_propagates(stmt, sp, src) && return false
        _stmt_fail_closed_return(stmt, sp, src) && return false
        summary(stmt) == "if" && _if_else_propagates(stmt, sp, src) && return false
        _stmt_acceptable_warn_handling(stmt, sp, src; warn_counts = warn_counts_as_handling) && continue
        any_non_handling = true
        if summary(stmt) == "if" && _if_without_else(stmt, sp)
            later_propagates = any(
                j -> begin
                    st2, sp2 = stmts[j]
                    _expr_always_propagates(st2, sp2, src) ||
                        _stmt_fail_closed_return(st2, sp2, src)
                end,
                (i + 1):length(stmts),
            )
            later_propagates || return true
            continue
        end
        _stmt_is_warn_only(stmt, sp, src; warn_counts = warn_counts_as_handling) && return true
    end
    return any_non_handling
end

function catch_var_dodge_name(var::Union{Nothing, Symbol})
    var === nothing && return false
    var == :anonymous && return true
    vs = String(var)
    return vs == "_" || startswith(vs, "_")
end

function catch_swallows_exception(
        body::GreenNode,
        pos::Int,
        src::AbstractString;
        warn_counts_as_handling::Bool,
    )
    return _catch_body_swallows(body, pos, src; warn_counts_as_handling = warn_counts_as_handling)
end
