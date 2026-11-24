const HUMAN_LEVEL_RED = (:forbid, :deny)
const HUMAN_LEVEL_YELLOW = (:warn,)

function active_violations(vs::Vector{Violation})
    out = Violation[]
    for d in vs
        is_violation_hit(d) || continue
        push!(out, d)
    end
    return out
end

function diag_sort_key(d::Violation)
    return (d.path, d.span, d.rule_id, d.fingerprint)
end

function violations_by_rule(vs::Vector{Violation})
    by = Dict{String, Vector{Violation}}()
    for d in vs
        push!(get!(by, d.rule_id, Violation[]), d)
    end
    for ds in values(by)
        sort!(ds; by = diag_sort_key)
    end
    return sort(collect(by); by = first)
end

function rule_violation_total(ceilings::CeilingEntry, rule_id::String)
    bucket = get(ceilings.violations, rule_id, nothing)
    bucket === nothing && return 0
    return sum(values(bucket))
end

function format_span_loc(d::Violation)
    sl = d.span
    return "$(d.path):$(sl.start_line):$(sl.start_col)-$(sl.end_line):$(sl.end_col)"
end

function source_line_at(root::AbstractString, d::Violation)
    path = joinpath(root, d.path)
    !isfile(path) && return ""
    source = normalize_source(read(path, String))
    lines = split(source, '\n')
    d.anchor_line > length(lines) && return ""
    return String(lines[d.anchor_line])
end

function underline_for_span(line::AbstractString, span::Span)
    isempty(line) && return ""
    n = length(line)
    sc = clamp(span.start_col, 1, max(n, 1))
    ec = clamp(span.end_col, sc, max(n, 1))
    buf = IOBuffer()
    for col in 1:n
        if col < sc
            write(buf, ' ')
        elseif col <= ec
            write(buf, '^')
        end
    end
    return String(take!(buf))
end

function color_enabled(io::IO)
    return get(io, :color, false)
end

function emit_plain_or_styled(io::IO, plain::AbstractString; color = nothing, bold = false)
    color_enabled(io) || return plain
    color === nothing && !bold && return plain
    buf = IOBuffer()
    ioctx = IOContext(buf, :color => true)
    if color === nothing
        printstyled(ioctx, plain; bold = bold)
    else
        printstyled(ioctx, plain; color = color, bold = bold)
    end
    return String(take!(buf))
end

function config_source_base_label(cs::ConfigSource)
    cs.kind == :git_ref && !isempty(cs.ref) && return cs.ref
    cs.kind == :path && !isempty(cs.path) && return cs.path
    return string(cs.kind)
end

function snippet_for_violation(root::AbstractString, d::Violation)
    path = joinpath(root, d.path)
    !isfile(path) && return ""
    source = normalize_source(read(path, String))
    lines = split(source, '\n')
    d.anchor_line > length(lines) && return ""
    line = String(lines[d.anchor_line])
    return strip(slice_line_codepoint_cols(line, d.span.start_col, d.span.end_col))
end
