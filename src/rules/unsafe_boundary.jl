using JuliaSyntax: GreenNode, head, is_infix_op_call, span

const _UNSAFE_BOUNDARY_INTENT =
    "Keep runtime evaluation, metaprogramming escapes, and FFI calls inside reviewed module or path boundaries."
const _UNSAFE_BOUNDARY_DO_NOT =
    "Alias Core.eval to a local name, pass eval/Meta.parse/ccall/invokelatest as values, split strings, Expr(:call,:eval,...), or hide calls outside allow_modules / allow_globs."

const _INDIRECT_EVAL_MODULES = Set(["Base", "Core"])

const _ALLOWED_BOUNDARY_QUALIFIERS = Set(["", "Base", "Core", "Meta", "Base.Meta", "Core.Meta"])

function _qualified_call_parts(fname::AbstractString)
    parts = split(strip(fname), '.')
    isempty(parts) && return ("", "")
    leaf = parts[end]
    qual = length(parts) == 1 ? "" : join(parts[1:(end - 1)], ".")
    return (qual, leaf)
end

function _allowed_boundary_qualifier(qual::AbstractString)
    return qual in _ALLOWED_BOUNDARY_QUALIFIERS
end

"""Match dotted call / ref names on the leaf identifier and an allowed qualifier prefix."""
function _matches_qualified_leaf(fname::AbstractString, leaf::AbstractString)
    qual, l = _qualified_call_parts(fname)
    return l == leaf && _allowed_boundary_qualifier(qual)
end

function _matches_meta_parse_call(fname::AbstractString)
    qual, leaf = _qualified_call_parts(fname)
    return leaf == "parse" &&
        qual in ("Meta", "Base.Meta", "Core.Meta") &&
        _allowed_boundary_qualifier(qual)
end

function _macro_qualified_parts(mname::AbstractString)
    n = strip(mname)
    startswith(n, "@") && return ("", n[2:end])
    if occursin(".@", n)
        parts = split(n, ".@"; limit = 2)
        return (parts[1], parts[2])
    end
    return ("", "")
end

function _matches_qualified_macro(mname::AbstractString, leaf::AbstractString)
    qual, base = _macro_qualified_parts(mname)
    return base == leaf && _allowed_boundary_qualifier(qual)
end

const _BOUNDARY_VALUE_LEAVES = Set(["eval", "ccall", "invokelatest"])

function _is_boundary_value_ref(refname::AbstractString)
    refname == "" && return false
    qual, leaf = _qualified_call_parts(refname)
    !_allowed_boundary_qualifier(qual) && return false
    leaf in _BOUNDARY_VALUE_LEAVES && return true
    return leaf == "parse" && qual in ("Meta", "Base.Meta", "Core.Meta")
end

function _value_ref_name(node::GreenNode, src::AbstractString, pos::Int)
    s = summary(node)
    if s == "."
        return _dot_callee_name(node, src, pos)
    elseif s == "Identifier"
        return _identifier_name(node, src, pos)
    end
    return ""
end

function _assignment_binding_parts(node::GreenNode, pos::Int)
    summary(node) == "=" || return (nothing, 0, nothing, 0)
    lhs = rhs = nothing
    lpos = rpos = 0
    for (c, p) in _walk_kids(node, pos)
        JuliaSyntax.is_trivia(head(c)) && continue
        if lhs === nothing
            lhs = c
            lpos = p
        else
            rhs = c
            rpos = p
            break
        end
    end
    return (lhs, lpos, rhs, rpos)
end

function _lhs_binding_ident(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "Identifier" || return ""
    return _identifier_name(node, src, pos)
end

function _walk_kids(node::GreenNode, pos::Int)
    return _child_positions(node, pos)[1]
end

function _macro_ref_name(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "macro_name" || return ""
    parts = String[]
    for (c, p) in _walk_kids(node, pos)
        is_leaf(c) && push!(parts, _identifier_name(c, src, p))
    end
    if !isempty(parts)
        return all(p -> p == "@", parts) ? "@" : (parts[1] == "@" ? "@" * join(parts[2:end]) : join(parts, ""))
    end
    for (c, p) in _walk_kids(node, pos)
        if summary(c) == "."
            ids = String[]
            for (cc, cpp) in _walk_kids(c, p)
                is_leaf(cc) && push!(ids, _identifier_name(cc, src, cpp))
            end
            return join(ids, ".")
        end
    end
    return ""
end

function _macrocall_name(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "macrocall" || return ""
    mname = ""
    for (c, p) in _walk_kids(node, pos)
        s = summary(c)
        if s == "."
            parts = String[]
            macro_leaf = ""
            for (cc, cpp) in _walk_kids(c, p)
                if summary(cc) == "macro_name"
                    macro_leaf = _macro_ref_name(cc, src, cpp)
                elseif is_leaf(cc)
                    push!(parts, _identifier_name(cc, src, cpp))
                end
            end
            !isempty(macro_leaf) && return join(parts, ".") * ".@" * macro_leaf
        elseif s == "macro_name"
            mname = _macro_ref_name(c, src, p)
        end
    end
    mname == "" && return ""
    startswith(mname, "@") && return mname
    return "@" * mname
end

function _dot_callee_parts(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "." || return String[]
    parts = String[]
    for (cc, cpp) in _walk_kids(node, pos)
        if summary(cc) == "."
            append!(parts, _dot_callee_parts(cc, src, cpp))
        elseif summary(cc) == "Identifier"
            push!(parts, _identifier_name(cc, src, cpp))
        end
    end
    return parts
end

function _dot_callee_name(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "." || return ""
    parts = _dot_callee_parts(node, src, pos)
    isempty(parts) && return ""
    txt = join(parts, ".")
    occursin("...", txt) && length(parts) >= 2 && return parts[1] * "." * parts[end]
    return txt
end

function _call_expr_parts(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "call" || return ("", GreenNode[], Int[])
    is_infix_op_call(head(node)) && return ("", GreenNode[], Int[])
    fname = ""
    args = GreenNode[]
    argpos = Int[]
    for (c, p) in _walk_kids(node, pos)
        JuliaSyntax.is_trivia(head(c)) && continue
        if isempty(fname)
            s = summary(c)
            if s == "."
                fname = _dot_callee_name(c, src, p)
                isempty(fname) && return ("", GreenNode[], Int[])
            elseif is_leaf(c) || s == "macro"
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

function _quote_symbol_name(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "quote" || return nothing
    for (c, p) in _walk_kids(node, pos)
        JuliaSyntax.is_trivia(head(c)) && continue
        summary(c) == "Identifier" && return _identifier_name(c, src, p)
        summary(c) == "quote" && return _quote_symbol_name(c, src, p)
    end
    return nothing
end

function _expr_has_string_interpolation(node::GreenNode, pos::Int)
    summary(node) == "string" && return _string_node_interpolated(node, pos)
    for (c, p) in _walk_kids(node, pos)
        JuliaSyntax.is_trivia(head(c)) && continue
        _expr_has_string_interpolation(c, p) && return true
    end
    return false
end

function _is_static_eval_arg(node::GreenNode, src::AbstractString, pos::Int)
    s = summary(node)
    if s == "string"
        return !_string_node_interpolated(node, pos)
    elseif s in ("Integer", "Float", "character")
        return true
    elseif s == "quote"
        sym = _quote_symbol_name(node, src, pos)
        sym !== nothing && return true
        for (c, p) in _walk_kids(node, pos)
            summary(c) == "parens" || continue
            for (cc, _) in _walk_kids(c, p)
                summary(cc) == "Identifier" && return true
            end
        end
        return false
    elseif s == "tuple" || s == "vect"
        any = false
        for (c, p) in _walk_kids(node, pos)
            JuliaSyntax.is_trivia(head(c)) && continue
            sk = string(kind(c))
            sk in ("()", ",") && continue
            any = true
            _is_static_eval_arg(c, src, p) || return false
        end
        return any
    end
    return false
end

"""Top-level `@eval` over quotes / literals without runtime interpolation (excluded)."""
function _top_level_literal_at_eval(node::GreenNode, src::AbstractString, pos::Int, at_toplevel::Bool)
    at_toplevel || return false
    summary(node) != "macrocall" && return false
    mname = _macrocall_name(node, src, pos)
    _matches_qualified_macro(mname, "eval") || return false
    args = GreenNode[]
    argpos = Int[]
    seen_name = false
    for (c, p) in _walk_kids(node, pos)
        JuliaSyntax.is_trivia(head(c)) && continue
        if !seen_name
            s = summary(c)
            if s in ("macro_name", "macro", ".")
                seen_name = true
                continue
            end
        end
        push!(args, c)
        push!(argpos, p)
    end
    !isempty(args) || return false
    for (c, p) in zip(args, argpos)
        _is_static_eval_arg(c, src, p) || return false
    end
    return true
end

function _module_decl_ident(node::GreenNode, src::AbstractString, pos::Int)
    summary(node) == "module" || return nothing
    for (c, p) in _walk_kids(node, pos)
        JuliaSyntax.is_trivia(head(c)) && continue
        summary(c) == "Identifier" && return _identifier_name(c, src, p)
    end
    return nothing
end

function _in_allowed_module(stack::Vector{String}, allow::Vector{String})
    qual = join(stack, ".")
    for a in allow
        a == qual && return true
        !isempty(qual) && startswith(qual, a * ".") && return true
    end
    return false
end

const _UNSAFE_MACRO_SUFFIXES = Set(["eval", "inbounds", "generated", "ccall", "assume_effects"])

function _unsafe_macro_label(name::AbstractString)
    qual, leaf = _macro_qualified_parts(name)
    !_allowed_boundary_qualifier(qual) && return ""
    leaf in _UNSAFE_MACRO_SUFFIXES || return ""
    return qual == "" ? "@" * leaf : qual * ".@" * leaf
end

const _JULIA_UNSAFE_CALLEES = Set(
    [
        "unsafe_load",
        "unsafe_store!",
        "unsafe_convert",
        "unsafe_wrap",
        "unsafe_string",
        "unsafe_copyto!",
        "unsafe_read",
        "unsafe_write",
        "unsafe_trunc",
        "unsafe_truncating",
        "unsafe_pointer_to_objref",
        "unsafe_array",
        "unsafe_trunc",
        "unsafe_debuginfo",
    ]
)

function _julia_unsafe_intrinsic_callee(fname::AbstractString)
    qual, leaf = _qualified_call_parts(fname)
    !_allowed_boundary_qualifier(qual) && return false
    return leaf in _JULIA_UNSAFE_CALLEES || occursin(r"^unsafe_[a-z]+[!?]?$", leaf)
end

function _indirect_eval_field_call(
        fname::AbstractString,
        args::Vector{GreenNode},
        argpos::Vector{Int},
        src::AbstractString,
    )
    fname == "getfield" || fname == "getproperty" || return false
    length(args) < 2 && return false
    modname = ""
    if summary(args[1]) == "Identifier"
        modname = _identifier_name(args[1], src, argpos[1])
    end
    modname in _INDIRECT_EVAL_MODULES || return false
    return _quote_symbol_name(args[2], src, argpos[2]) == "eval"
end

function _eval_call_is_runtime(node::GreenNode, src::AbstractString, pos::Int, args, argpos)
    _expr_has_string_interpolation(node, pos) && return true
    isempty(args) && return true
    for (c, p) in zip(args, argpos)
        _is_static_eval_arg(c, src, p) || return true
    end
    return false
end

mutable struct UnsafeBoundaryWalk
    source::String
    allow_modules::Vector{String}
    module_stack::Vector{String}
    at_toplevel::Bool
    dangerous_aliases::Dict{String, String}
    hits::Vector{Tuple{Int, Int, String}}
end

function _allow_site(ctx::UnsafeBoundaryWalk)
    return _in_allowed_module(ctx.module_stack, ctx.allow_modules)
end

function _record_hit!(ctx::UnsafeBoundaryWalk, pos::Int, node::GreenNode, msg::String)
    _allow_site(ctx) && return
    byte_end = pos + span(node) - 1
    push!(ctx.hits, (pos, byte_end, msg))
    return nothing
end

function _walk_unsafe_boundary!(node::GreenNode, pos::Int, ctx::UnsafeBoundaryWalk)
    s = summary(node)

    if s == "module"
        ident = _module_decl_ident(node, ctx.source, pos)
        if ident !== nothing
            push!(ctx.module_stack, ident)
            for (c, p) in _walk_kids(node, pos)
                JuliaSyntax.is_trivia(head(c)) && continue
                summary(c) == "block" && _walk_unsafe_boundary!(c, p, ctx)
            end
            pop!(ctx.module_stack)
            return
        end
    end

    if s == "function"
        old_top = ctx.at_toplevel
        ctx.at_toplevel = false
        head_call_seen = false
        for (c, p) in _walk_kids(node, pos)
            JuliaSyntax.is_trivia(head(c)) && continue
            if !head_call_seen && summary(c) == "call"
                head_call_seen = true
                _, args, argpos = _call_expr_parts(c, ctx.source, p)
                for (ac, ap) in zip(args, argpos)
                    _walk_unsafe_boundary!(ac, ap, ctx)
                end
            else
                _walk_unsafe_boundary!(c, p, ctx)
            end
        end
        ctx.at_toplevel = old_top
        return
    end

    if s == "="
        lhs, lpos, rhs, rpos = _assignment_binding_parts(node, pos)
        if lhs !== nothing && rhs !== nothing
            lhs_name = _lhs_binding_ident(lhs, ctx.source, lpos)
            refname = _value_ref_name(rhs, ctx.source, rpos)
            if _is_boundary_value_ref(refname)
                _record_hit!(ctx, rpos, rhs, "boundary value alias ($refname)")
                if lhs_name != ""
                    ctx.dangerous_aliases[lhs_name] = refname
                end
            end
        end
    end

    if s == "macrocall"
        mname = _macrocall_name(node, ctx.source, pos)
        macro_label = _unsafe_macro_label(mname)
        if !isempty(macro_label)
            if _matches_qualified_macro(mname, "eval") &&
                    _top_level_literal_at_eval(node, ctx.source, pos, ctx.at_toplevel)
                # allowed top-level literal `@eval`
            else
                _record_hit!(ctx, pos, node, "unsafe boundary escape ($macro_label)")
            end
        end
    elseif s == "call"
        fname, args, argpos = _call_expr_parts(node, ctx.source, pos)
        if haskey(ctx.dangerous_aliases, fname)
            _record_hit!(ctx, pos, node, "call via value alias ($fname)")
        elseif _julia_unsafe_intrinsic_callee(fname)
            _record_hit!(ctx, pos, node, "unsafe_* call ($fname)")
        elseif _matches_qualified_leaf(fname, "eval")
            _eval_call_is_runtime(node, ctx.source, pos, args, argpos) &&
                _record_hit!(ctx, pos, node, "runtime eval ($fname)")
        elseif _matches_meta_parse_call(fname)
            _record_hit!(ctx, pos, node, "Meta.parse boundary escape")
        elseif _matches_qualified_leaf(fname, "ccall")
            _record_hit!(ctx, pos, node, "ccall boundary escape")
        elseif _matches_qualified_leaf(fname, "invokelatest")
            _record_hit!(ctx, pos, node, "invokelatest boundary escape")
        elseif fname == "getfield" || fname == "getproperty"
            _indirect_eval_field_call(fname, args, argpos, ctx.source) &&
                _record_hit!(ctx, pos, node, "indirect eval via $fname")
        end
        for (arg, ap) in zip(args, argpos)
            argref = _value_ref_name(arg, ctx.source, ap)
            _is_boundary_value_ref(argref) &&
                _record_hit!(ctx, ap, arg, "boundary value reference ($argref)")
        end
    end

    if s == "module"
        return
    end

    child_toplevel = ctx.at_toplevel && s == "toplevel"
    for (c, p) in _walk_kids(node, pos)
        JuliaSyntax.is_trivia(head(c)) && continue
        if child_toplevel && summary(c) != "module"
            saved = ctx.at_toplevel
            ctx.at_toplevel = true
            _walk_unsafe_boundary!(c, p, ctx)
            ctx.at_toplevel = saved
        else
            ctx.at_toplevel = false
            _walk_unsafe_boundary!(c, p, ctx)
        end
    end
    return nothing
end

function diagnose_unsafe_boundary(
        fc::FileContext,
        policy::PolicyBundle,
        eff_level::Symbol,
    )
    cfg = policy.unsafe_boundary
    source = fc.parsed.normalized
    tree = parse_source(source; filename = fc.parsed.path)
    ctx = UnsafeBoundaryWalk(
        source,
        cfg.allow_modules,
        String[],
        true,
        Dict{String, String}(),
        Tuple{Int, Int, String}[],
    )
    _walk_unsafe_boundary!(tree, 1, ctx)
    intent = isempty(cfg.intent) ? _UNSAFE_BOUNDARY_INTENT : cfg.intent
    do_not = isempty(cfg.do_not) ? _UNSAFE_BOUNDARY_DO_NOT : cfg.do_not
    diags = Violation[]
    seen = Set{Tuple{Int, Int}}()
    for (bs, be, msg) in ctx.hits
        key = (bs, be)
        key in seen && continue
        push!(seen, key)
        _push_builtin_violation!(
            diags,
            "unsafe-boundary",
            :agentrulelint,
            eff_level,
            fc.parsed.path,
            source,
            bs,
            be,
            msg,
            intent,
            do_not,
        )
    end
    return diags
end
