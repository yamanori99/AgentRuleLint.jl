const _textwidth = Base.Unicode.textwidth

const OUTPUT_WIDTH_CAP = Ref(80)
const OUTPUT_WRAP_PROSE = Ref(true)
const OUTPUT_TRUNCATE_QUOTED = Ref(true)

const ELLIPSIS_CHAR = "…"

_ansi_pattern = r"\e\[[0-9;]*m"

function strip_ansi(s::AbstractString)
    return replace(s, _ansi_pattern => "")
end

function visible_textwidth(s::AbstractString)
    return _textwidth(strip_ansi(s))
end

"""
    output_displaysize(io::IO=stdout) -> Int

Return `min(cols, OUTPUT_WIDTH_CAP[])` where `cols` is from `displaysize(io)`
(TTY, else `ENV["COLUMNS"]`, else 80).
"""
function output_displaysize(io::IO = stdout)
    cols, _ = displaysize(io)
    return min(cols, OUTPUT_WIDTH_CAP[])
end

function resolve_output_width(io::IO = stdout; output_width::Union{Nothing, Int} = nothing)
    output_width !== nothing && return output_width
    return output_displaysize(io)
end

function _prose_budget(prefix::AbstractString, width::Int)
    w = width - visible_textwidth(prefix)
    return max(w, 1)
end

function _char_display_width(c::AbstractChar)
    return _textwidth(c)
end

function _substr_chars(s::AbstractString, i::Integer, j::Integer)
    return s[i:j]
end

function _substring_through_index(s::AbstractString, last_i::Integer)
    fi = firstindex(s)
    last_i < fi && return ""
    return _substr_chars(s, fi, last_i)
end

function _truncate_chars(text::AbstractString, maxw::Int; with_ellipsis::Bool = true)
    isempty(text) && return ""
    maxw <= 0 && return with_ellipsis ? ELLIPSIS_CHAR : ""
    reserve = with_ellipsis ? visible_textwidth(ELLIPSIS_CHAR) : 0
    limit = maxw - reserve
    limit <= 0 && return with_ellipsis ? ELLIPSIS_CHAR : ""
    w = 0
    last_i = nothing
    stopped_early = false
    for i in eachindex(text)
        cw = _char_display_width(text[i])
        if w + cw > limit
            stopped_early = true
            break
        end
        w += cw
        last_i = i
    end
    last_i === nothing && return with_ellipsis ? ELLIPSIS_CHAR : ""
    body = _substring_through_index(text, last_i)
    needs_ellipsis = with_ellipsis && stopped_early
    return needs_ellipsis ? body * ELLIPSIS_CHAR : body
end

function _wrap_char_chunks(text::AbstractString, budget::Int)
    isempty(text) && return [""]
    lines = String[]
    line_start = firstindex(text)
    last_i = lastindex(text)
    while line_start <= last_i
        w = 0
        chunk_end = nothing
        i = line_start
        while i <= last_i
            cw = _char_display_width(text[i])
            if w + cw > budget
                break
            end
            w += cw
            chunk_end = i
            i === last_i && break
            i = nextind(text, i)
        end
        chunk_end === nothing && begin
            chunk_end = line_start
        end
        push!(lines, _substr_chars(text, line_start, chunk_end))
        chunk_end >= last_i && break
        line_start = nextind(text, chunk_end)
    end
    isempty(lines) && push!(lines, "")
    return lines
end

function _wrap_words(text::AbstractString, budget::Int)
    isempty(text) && return [""]
    words = String[]
    for m in eachmatch(r"\S+", String(text))
        push!(words, m.match)
    end
    isempty(words) && return [""]
    lines = String[]
    cur = ""
    for word in words
        candidate = isempty(cur) ? word : cur * " " * word
        if visible_textwidth(candidate) <= budget
            cur = candidate
        elseif isempty(cur)
            if visible_textwidth(word) <= budget
                cur = word
            else
                append!(lines, _wrap_char_chunks(word, budget))
            end
        else
            push!(lines, cur)
            if visible_textwidth(word) <= budget
                cur = word
            else
                append!(lines, _wrap_char_chunks(word, budget))
                cur = ""
            end
        end
    end
    !isempty(cur) && push!(lines, cur)
    return lines
end

function wrap_prose_lines(
        first_prefix::AbstractString,
        cont_prefix::AbstractString,
        text::AbstractString,
        width::Int;
        wrap::Bool = OUTPUT_WRAP_PROSE[],
    )
    budget = _prose_budget(first_prefix, width)
    chunks = wrap ? _wrap_words(text, budget) : [String(text)]
    lines = String[]
    for (i, chunk) in enumerate(chunks)
        prefix = i == 1 ? first_prefix : cont_prefix
        push!(lines, prefix * chunk)
    end
    return lines
end

function wrap_labeled_prose(
        margin::AbstractString,
        label::AbstractString,
        text::AbstractString,
        width::Int;
        kwargs...,
    )
    first_prefix = string(margin, label)
    cont_prefix = string(margin, repeat(' ', _textwidth(label)))
    return wrap_prose_lines(first_prefix, cont_prefix, text, width; kwargs...)
end

function truncate_quoted_line(
        prefix::AbstractString,
        body::AbstractString,
        width::Int;
        truncate::Bool = OUTPUT_TRUNCATE_QUOTED[],
    )
    line = string(prefix, body)
    !truncate && return line
    visible_textwidth(line) <= width && return line
    budget = width - visible_textwidth(prefix) - visible_textwidth(ELLIPSIS_CHAR)
    budget < 1 && return string(prefix, ELLIPSIS_CHAR)
    return string(prefix, _truncate_chars(body, budget, with_ellipsis = true))
end

function println_wrapped_prose(buf::IO, prefixes, text::AbstractString, width::Int)
    first_prefix, cont_prefix = prefixes
    for ln in wrap_prose_lines(first_prefix, cont_prefix, text, width)
        println(buf, ln)
    end
    return nothing
end

function println_wrapped_labeled(buf::IO, margin::AbstractString, label::AbstractString, text::AbstractString, width::Int)
    for ln in wrap_labeled_prose(margin, label, text, width)
        println(buf, ln)
    end
    return nothing
end
