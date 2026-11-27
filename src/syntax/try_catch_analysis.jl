

struct TryCatchSite
    try_pos::Int
    try_line::Int
    catch_var::Union{Nothing, Symbol}
    catch_body::Union{Nothing, GreenNode}
    catch_body_pos::Int
end

function _catch_binding_name(node::GreenNode, src::AbstractString, pos::Int)
    if kind(node) == KPlaceholder
        return :anonymous
    elseif kind(node) == KIdentifier
        nm = _identifier_name(node, src, pos)
        isempty(nm) && return :anonymous
        return Symbol(nm)
    end
    return nothing
end

function _try_catch_site(node::GreenNode, pos::Int, src::AbstractString)::Union{Nothing, TryCatchSite}
    kind(node) == KTry || return nothing
    catch_node = nothing
    catch_pos = 0
    for (c, p) in _child_positions(node, pos)[1]
        if kind(c) == KCatch
            catch_node = c
            catch_pos = p
        end
    end
    catch_node === nothing && return nothing
    catch_var = nothing
    catch_body = nothing
    catch_body_pos = 0
    for (c, p) in _child_positions(catch_node, catch_pos)[1]
        if kind(c) == KIdentifier || kind(c) == KPlaceholder
            catch_var = _catch_binding_name(c, src, p)
        elseif kind(c) == KBlock
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
        kind(c) in _STMT_TRIVIA_KINDS && continue
        push!(out, (c, p))
    end
    return out
end

function _callee_name(node::GreenNode, pos::Int, src::AbstractString)
    kind(node) != KCall && return ""
    for (c, _) in _child_positions(node, pos)[1]
        kind(c) == KIdentifier && return _identifier_name(c, src, pos)
    end
    return ""
end

function _call_first_identifier_arg(node::GreenNode, pos::Int, src::AbstractString)
    kind(node) != KCall && return ""
    saw_paren = false
    for (c, p) in _child_positions(node, pos)[1]
        if kind(c) == KOpenParen
            saw_paren = true
            continue
        end
        if !saw_paren
            continue
        end
        kind(c) == KIdentifier && return _identifier_name(c, src, p)
        kind(c) == KComma && continue
        break
    end
    return ""
end

function _catch_var_type_test(lhs::GreenNode, lpos::Int, src::AbstractString, catch_var::Union{Nothing, Symbol})
    (catch_var === nothing || catch_var == :anonymous) && return false
    vname = String(catch_var)
    if kind(lhs) == KCall
        cn = _callee_name(lhs, lpos, src)
        if cn == "isa"
            return _call_first_identifier_arg(lhs, lpos, src) == vname
        end
        ids = String[]
        for (c, p) in _child_positions(lhs, lpos)[1]
            kind(c) == KIdentifier && push!(ids, _identifier_name(c, src, p))
        end
        return length(ids) >= 3 && ids[1] == vname && ids[2] == "isa"
    end
    return false
end

function _or_chain_catchvar_isa_rethrow(node::GreenNode, pos::Int, src::AbstractString, catch_var::Union{Nothing, Symbol})
    kind(node) != KOr && return false
    saw_or = false
    lhs = nothing
    lhs_pos = 0
    rhs = nothing
    rhs_pos = 0
    for (c, p) in _child_positions(node, pos)[1]
        if kind(c) == KOr
            saw_or = true
            continue
        end
        syntax_is_trivia(c) && continue
        if !saw_or && lhs === nothing
            lhs = c
            lhs_pos = p
        elseif saw_or && rhs === nothing
            rhs = c
            rhs_pos = p
            break
        end
    end
    (lhs === nothing || rhs === nothing) && return false
    _catch_var_type_test(lhs, lhs_pos, src, catch_var) || return false
    return kind(rhs) == KCall && _callee_name(rhs, rhs_pos, src) == "rethrow"
end

function _is_rethrow_or_throw(node::GreenNode, pos::Int, src::AbstractString)
    nm = _callee_name(node, pos, src)
    return nm == "rethrow" || nm == "throw"
end

function _propagating_call(node::GreenNode, pos::Int, src::AbstractString)
    return _is_rethrow_or_throw(node, pos, src)
end

function _macrocall_name(node::GreenNode, pos::Int, src::AbstractString)
    kind(node) != KMacrocall && return ""
    for (c, p) in _child_positions(node, pos)[1]
        kind(c) == KMacroName || continue
        for (cc, cp) in _child_positions(c, p)[1]
            kind(cc) == KIdentifier && return _identifier_name(cc, src, cp)
        end
    end
    return ""
end

function _macrocall_has_exception_kw(node::GreenNode, pos::Int, src::AbstractString)
    for (c, cp) in _child_positions(node, pos)[1]
        kind(c) == KAssign || continue
        for (kc, kp) in _child_positions(c, cp)[1]
            kind(kc) == KIdentifier || continue
            _identifier_name(kc, src, kp) == "exception" && return true
        end
    end
    return false
end

function _macro_is_warn(node::GreenNode, pos::Int, src::AbstractString)
    return kind(node) == KMacrocall && _macrocall_name(node, pos, src) == "warn"
end

function _macro_warn_has_exception_kw(node::GreenNode, pos::Int, src::AbstractString)
    return _macro_is_warn(node, pos, src) && _macrocall_has_exception_kw(node, pos, src)
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

function _stmt_unconditional_return(node::GreenNode)
    return kind(node) == KReturn
end

function _else_block_after_else_keyword(node::GreenNode, pos::Int)
    pending = false
    for (c, p) in _child_positions(node, pos)[1]
        if kind(c) == KElse
            pending = true
            continue
        end
        if pending && kind(c) == KBlock
            return c, p
        end
        pending = false
    end
    return nothing, 0
end

function _is_elseif_clause(node::GreenNode)
    kind(node) != KElseif && return false
    ch = syntax_children(node)
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
    kind(node) != KIf && return nothing, 0
    for (c, p) in _child_positions(node, pos)[1]
        _is_elseif_clause(c) || continue
        return _elseif_chain_final_else(c, p)
    end
    return _else_block_after_else_keyword(node, pos)
end

function _if_else_propagates(node::GreenNode, pos::Int, src::AbstractString, catch_var::Union{Nothing, Symbol})
    else_block, else_pos = _if_final_else_block(node, pos)
    else_block === nothing && return false
    for (st, sp) in _block_statements(else_block, else_pos)
        _expr_always_propagates(st, sp, src, catch_var) && return true
    end
    return false
end

function _expr_always_propagates(
        node::GreenNode,
        pos::Int,
        src::AbstractString,
        catch_var::Union{Nothing, Symbol},
    )
    if kind(node) == KCall
        return _propagating_call(node, pos, src)
    elseif kind(node) == KOr
        return _or_chain_catchvar_isa_rethrow(node, pos, src, catch_var)
    elseif kind(node) == KIf
        return _if_else_propagates(node, pos, src, catch_var)
    end
    return false
end

function _if_without_else(node::GreenNode, pos::Int)
    kind(node) != KIf && return false
    return _if_final_else_block(node, pos)[1] === nothing
end

function _stmt_acceptable_warn_handling(node::GreenNode, pos::Int, src::AbstractString; warn_counts::Bool)
    return warn_counts && _macro_warn_has_exception_kw(node, pos, src)
end

function _stmt_may_propagate(
        stmt::GreenNode,
        sp::Int,
        src::AbstractString,
        catch_var::Union{Nothing, Symbol},
    )
    return _expr_always_propagates(stmt, sp, src, catch_var)
end

function _catch_body_swallows(
        body::GreenNode,
        pos::Int,
        src::AbstractString,
        catch_var::Union{Nothing, Symbol};
        warn_counts_as_handling::Bool,
    )
    stmts = _block_statements(body, pos)
    isempty(stmts) && return true
    any_non_handling = false
    reachable = true
    for (i, (stmt, sp)) in enumerate(stmts)
        reachable || break
        _stmt_may_propagate(stmt, sp, src, catch_var) && return false
        kind(stmt) == KIf && _if_else_propagates(stmt, sp, src, catch_var) && return false
        _stmt_acceptable_warn_handling(stmt, sp, src; warn_counts = warn_counts_as_handling) && continue
        any_non_handling = true
        if kind(stmt) == KIf && _if_without_else(stmt, sp)
            later_propagates = any(
                j -> _stmt_may_propagate(stmts[j][1], stmts[j][2], src, catch_var),
                (i + 1):length(stmts),
            )
            later_propagates || return true
            continue
        end
        _stmt_is_warn_only(stmt, sp, src; warn_counts = warn_counts_as_handling) && return true
        _stmt_unconditional_return(stmt) && (reachable = false)
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
        src::AbstractString,
        catch_var::Union{Nothing, Symbol};
        warn_counts_as_handling::Bool,
    )
    return _catch_body_swallows(
        body,
        pos,
        src,
        catch_var;
        warn_counts_as_handling = warn_counts_as_handling,
    )
end
