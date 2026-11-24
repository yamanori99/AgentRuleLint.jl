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

function underline_for_span(line::AbstractString, span::Span; marker::Char = '^')
    isempty(line) && return ""
    n = length(line)
    sc = clamp(span.start_col, 1, max(n, 1))
    ec = clamp(span.end_col, sc, max(n, 1))
    buf = IOBuffer()
    for col in 1:n
        if col < sc
            write(buf, ' ')
        elseif col <= ec
            write(buf, marker)
        end
    end
    return String(take!(buf))
end

function human_console_level(level::Symbol)
    return level in HUMAN_LEVEL_YELLOW ? "Warning" : "Error"
end

function human_violation_phrase(n::Int)
    return n == 1 ? "1 violation" : "$n violations"
end

function human_ceiling_display(ceilings::CeilingEntry, rule_id::String)
    total = rule_violation_total(ceilings, rule_id)
    return string(total)
end

function human_policy_banner(result::CheckResult)
    cs = result.config_source
    base = if cs.kind == :git_ref && !isempty(cs.ref)
        sha = isempty(cs.sha) ? "?" : cs.sha
        "policy bundle base: $(cs.ref) @ $sha"
    elseif cs.kind == :path && !isempty(cs.path)
        "policy bundle base: $(cs.path)"
    elseif cs.kind == :builtin
        "policy bundle base: builtin"
    else
        "policy bundle base: $(string(cs.kind))"
    end
    return "AgentRuleLint v$(pkgversion(AgentRuleLint)) ($base, pos: utf8-codepoint-1based)"
end

function human_rule_footer(rule_id::String, origin::Symbol, config_path::AbstractString)
    if origin == :agentrulelint
        return "└ @ AgentRuleLint (run `agentrulelint explain $rule_id` for details)"
    elseif origin == :project
        cfg = isempty(config_path) ? ".AgentRuleLintConfig.toml" : config_path
        return "└ @ Project $cfg ([[project_rules]])"
    else
        return "└ @ $(origin_label(origin)) (run `agentrulelint explain $rule_id` for details)"
    end
end

function _human_gutter_prefixes(line_no::Int)
    num = string(line_no)
    line_prefix = "│" * repeat(' ', 5) * num * " │ "
    w = visible_textwidth(line_prefix)
    inner = w - visible_textwidth("│ ")
    inner < 1 && (inner = 1)
    ul_prefix = "│" * repeat(' ', inner - 1) * "│ "
    return line_prefix, ul_prefix
end

function _human_truncate_code(body::AbstractString, prefix::AbstractString, width::Int)
    budget = width - visible_textwidth(prefix)
    budget < 1 && return string(prefix, ELLIPSIS_CHAR)
    return string(prefix, _truncate_chars(body, budget, with_ellipsis = true))
end

function println_human_code_gutter(
        buf::IO,
        width::Int,
        line_no::Int,
        line::AbstractString,
        span::Span,
    )
    line_prefix, ul_prefix = _human_gutter_prefixes(line_no)
    src = _truncate_chars(line, width - visible_textwidth(line_prefix), with_ellipsis = true)
    println(buf, _human_truncate_code(src, line_prefix, width))
    ul_body = underline_for_span(src, span; marker = '~')
    !isempty(ul_body) || return nothing
    ul = strip(ul_body, ' ')
    isempty(ul) && return nothing
    println(buf, _human_truncate_code(ul, ul_prefix, width))
    return nothing
end

function human_summary_by_origin(groups)
    counts = Dict{String, Int}()
    for (_, ds) in groups
        label = origin_label(ds[1].origin)
        counts[label] = get(counts, label, 0) + 1
    end
    parts = String[]
    for (label, n) in sort(collect(counts))
        push!(parts, "$n $label")
    end
    return join(parts, ", ")
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
