const GreenNode = JuliaSyntax.GreenNode

"""
Single-pass constant string folder over `Meta.parseall` expressions.
Immune to rescan cycles; only evaluates literal subtrees.
"""
function try_fold_strings(ex)
    ex isa AbstractString && return String(ex)
    ex isa QuoteNode && return try_fold_strings(ex.value)
    ex isa Expr || return nothing
    h = ex.head
    if h == :call
        f = ex.args[1]
        if f === Base.:* || f == :(*)
            length(ex.args) < 3 && return nothing
            parts = String[]
            for i in 2:length(ex.args)
                v = try_fold_strings(ex.args[i])
                v === nothing && return nothing
                push!(parts, v)
            end
            return join(parts)
        elseif f === :string || f === :+
            parts = String[]
            for i in 2:length(ex.args)
                v = try_fold_strings(ex.args[i])
                v === nothing && return nothing
                push!(parts, v)
            end
            return join(parts)
        elseif f === :join
            length(ex.args) < 3 && return nothing
            xs = try
                eval(esc(ex.args[2]))
            catch
                return nothing
            end
            xs isa AbstractVector || return nothing
            delim = try_fold_strings(ex.args[3])
            delim === nothing && return nothing
            if length(ex.args) >= 4
                last_d = try_fold_strings(ex.args[4])
                last_d === nothing && return nothing
                return join(xs[1:(end - 1)], delim) * last_d * xs[end]
            end
            return join(xs, delim)
        elseif f === :String
            length(ex.args) != 2 && return nothing
            vec = try
                eval(esc(ex.args[2]))
            catch
                return nothing
            end
            return String(vec)
        elseif f === :reduce
            length(ex.args) < 3 && return nothing
            reducer = ex.args[2]
            red = reducer === :* || reducer === :string ? reducer :
                reducer isa Expr && reducer.head == :call && reducer.args[1] === :string ? :string :
                reducer isa Expr && reducer.head == :-> ? nothing : nothing
            red === nothing && return nothing
            coll = try
                eval(esc(ex.args[3]))
            catch
                return nothing
            end
            coll isa AbstractVector || return nothing
            if red === :*
                return foldreduce(coll) do a, b
                    string(a, b)
                end
            else
                return foldreduce(coll) do a, b
                    string(a) * string(b)
                end
            end
        end
    elseif h == :string
        parts = String[]
        for arg in ex.args
            if arg isa Symbol && startswith(string(arg), "#")
                continue
            end
            v = try_fold_strings(arg)
            v === nothing && return nothing
            push!(parts, v)
        end
        return join(parts)
    elseif h == :macrocall && ex.args[1] === :var"meta"
        return try_fold_strings(ex.args[3])
    end
    return nothing
end

function foldreduce(f, vec::AbstractVector)
    isempty(vec) && throw(ArgumentError("empty"))
    acc = vec[1]
    for i in 2:length(vec)
        acc = f(acc, vec[i])
    end
    return string(acc)
end

function collect_folded_strings(source::AbstractString)
    vals = String[]
    for line in split(source, '\n')
        line = strip(line)
        isempty(line) && continue
        try
            ex = Meta.parse(line)
            ex isa Expr || continue
            if ex.head == :(=)
                w = try_fold_strings(ex.args[2])
                w !== nothing && push!(vals, w)
            end
            v = try_fold_strings(ex)
            v !== nothing && push!(vals, v)
        catch
        end
    end
    return unique(vals)
end

function folded_string_literals(_tree::GreenNode, source::AbstractString; byte_offset::Int = 1)
    return collect_folded_strings(source)
end

function fold_expr(node::GreenNode, source::AbstractString; byte_offset::Int = 1, depth::Int = 0)
    vals = collect_folded_strings(source)
    return isempty(vals) ? nothing : first(vals)
end

function walk_gree(tree::GreenNode, source::AbstractString, cb; line_offset::Int = 1)
    for (i, ex) in enumerate(split(source, '\n'))
        cb(tree, source, 1, i)
    end
    return
end
