"""Normalize source text: BOM strip and CRLF to LF."""
function normalize_source(text::AbstractString)
    s = String(text)
    startswith(s, "\ufeff") && (s = s[4:end])
    return replace(s, "\r\n" => "\n", "\r" => "\n")
end

"""1-based UTF-8 codepoint column at byte index within `line` (1-based byte index on line)."""
function byte_to_col(line::AbstractString, byte_index::Int)
    byte_index < 1 && return 1
    byte_index > ncodeunits(line) + 1 && return length(line) + 1
    col = 1
    i = 1
    while i < byte_index && i <= ncodeunits(line)
        i = nextind(line, i)
        col += 1
    end
    return col
end

function line_byte_span(source::AbstractString, line_no::Int)
    start = 1
    for _ in 2:line_no
        nl = findnext('\n', source, start)
        nl === nothing && break
        start = nl + 1
    end
    stop = findnext('\n', source, start)
    stop === nothing && (stop = ncodeunits(source) + 1)
    line_text = source[start:prevind(source, stop)]
    return start, line_text, stop
end

function line_number_at_byte(source::AbstractString, byte_index::Int)
    line = 1
    pos = 1
    while pos < byte_index && pos <= ncodeunits(source)
        nl = findnext('\n', source, pos)
        nl === nothing && break
        if nl < byte_index
            line += 1
            pos = nl + 1
        else
            break
        end
    end
    return line
end

function position_at_byte(source::AbstractString, byte_index::Int)
    line = line_number_at_byte(source, byte_index)
    line_start, line_text, _ = line_byte_span(source, line)
    col = byte_to_col(line_text, byte_index - line_start + 1)
    return line, col
end

function span_from_byte_range(source::AbstractString, byte_start::Int, byte_end::Int)
    sl, sc = position_at_byte(source, byte_start)
    el, ec = position_at_byte(source, byte_end)
    return Span(sl, sc, el, ec)
end

function span_for_line(source::AbstractString, line_no::Int)
    _, line_text, _ = line_byte_span(source, line_no)
    ec = max(1, length(line_text))
    return line_text, Span(line_no, 1, line_no, ec)
end

function slice_source(source::AbstractString, byte_start::Int, byte_end::Int)
    byte_start < 1 && (byte_start = 1)
    byte_end > ncodeunits(source) && (byte_end = ncodeunits(source))
    byte_start > byte_end && return ""
    return source[byte_start:byte_end]
end
