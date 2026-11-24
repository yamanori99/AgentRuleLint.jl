const COMMENT_KIND = JuliaSyntax.K"Comment"

function whitespace_kind(k)
    return k == JuliaSyntax.K"Whitespace" || k == JuliaSyntax.K"NewlineWs"
end

"""Lines where the only non-whitespace token is a `Comment`."""
function standalone_comment_lines(source::AbstractString)
    source = normalize_source(source)
    out = Dict{Int, String}()
    line_no = 1
    start = 1
    while start <= ncodeunits(source)
        nl = findnext('\n', source, start)
        if nl === nothing
            line_text = source[start:end]
            stop = ncodeunits(source)
        else
            line_text = source[start:prevind(source, nl)]
            stop = nl
        end
        tokens = JuliaSyntax.tokenize(line_text; operators_as_identifiers = false)
        nontriv = JuliaSyntax.Token[]
        for t in tokens
            k = JuliaSyntax.kind(t)
            whitespace_kind(k) && continue
            push!(nontriv, t)
        end
        if length(nontriv) == 1 && JuliaSyntax.kind(nontriv[1]) == COMMENT_KIND
            raw = JuliaSyntax.untokenize(nontriv[1], line_text)
            body = strip(raw[2:end])
            out[line_no] = body
        end
        nl === nothing && break
        line_no += 1
        start = nl + 1
    end
    return out
end
