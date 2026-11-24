"""Normalize source text: BOM strip and CRLF to LF."""
function normalize_source(text::AbstractString)
    s = String(text)
    startswith(s, "\ufeff") && (s = s[4:end])
    return replace(s, "\r\n" => "\n", "\r" => "\n")
end

"""1-based codepoint column at byte index (after normalization)."""
function byte_to_col(line::AbstractString, byte_index::Int)
    byte_index < 1 && return 1
    byte_index > ncodeunits(line) + 1 && return lastindex(line) + 1
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

function span_for_line(source::AbstractString, line_no::Int)
    start, line_text, _ = line_byte_span(source, line_no)
    sc = 1
    ec = ncodeunits(line_text)
    ec == 0 && (ec = 1)
    return start, line_text, Span(line_no, sc, line_no, ec)
end
