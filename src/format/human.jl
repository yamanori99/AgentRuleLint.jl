function _human_level_styled(io::IO, level::Symbol)
    plain = string(level)
    color_enabled(io) || return plain
    if level in HUMAN_LEVEL_RED
        return emit_plain_or_styled(io, plain; color = :red)
    elseif level in HUMAN_LEVEL_YELLOW
        return emit_plain_or_styled(io, plain; color = :yellow)
    end
    return plain
end

function _human_rule_id_styled(io::IO, rule_id::AbstractString)
    color_enabled(io) || return String(rule_id)
    return emit_plain_or_styled(io, String(rule_id); color = :cyan)
end

function _human_group_header(
        io::IO,
        label::AbstractString,
        rule_id::AbstractString,
        level::Symbol,
        total::Int,
        ceiling_s::AbstractString,
    )
    rid = _human_rule_id_styled(io, rule_id)
    lvl = _human_level_styled(io, level)
    head = human_console_level(level)
    counts = human_violation_phrase(total)
    return "┌ $head: $label $rid [$lvl] ($counts, ceiling $ceiling_s)"
end

function format_human(
        result::CheckResult;
        root::AbstractString = pwd(),
        io::IO = stdout,
        output_width::Union{Nothing, Int} = nothing,
    )
    width = resolve_output_width(io; output_width = output_width)
    buf = IOBuffer()
    policy = resolve_policy(root)
    init_registry!(policy)
    ceilings = load_ceilings(root, policy)
    groups = violations_by_rule(active_violations(result.violations))
    max_hits = result.max_hits_per_rule
    cfg_label = result.config_source.path

    banner = human_policy_banner(result)
    if visible_textwidth(banner) <= width
        println(buf, banner)
    else
        for ln in wrap_prose_lines("", "", banner, width)
            println(buf, ln)
        end
    end
    println(buf)

    for (rule_id, ds) in groups
        d0 = ds[1]
        label = origin_label(d0.origin)
        total = length(ds)
        ceiling_s = human_ceiling_display(ceilings, rule_id)
        header = _human_group_header(io, label, rule_id, d0.level, total, ceiling_s)
        for ln in wrap_prose_lines("", "", header, width)
            println(buf, ln)
        end
        intent = d0.intent
        do_not = d0.do_not
        if isempty(intent) && haskey(BUILTIN_RULES, rule_id)
            spec = BUILTIN_RULES[rule_id]
            intent = spec.intent
            do_not = spec.do_not
        end
        !isempty(intent) &&
            println_wrapped_labeled(buf, "│   ", "intent: ", intent, width)
        !isempty(do_not) &&
            println_wrapped_labeled(buf, "│   ", "do_not: ", do_not, width)
        println(buf, "│")

        limit = min(total, max_hits)
        for i in 1:limit
            d = ds[i]
            loc_body = format_span_loc(d)
            (d.span == Span(1, 1, 1, 1) && d.anchor_line == 1) && (loc_body = d.path)
            for ln in wrap_prose_lines("", "", "│   $loc_body", width)
                println(buf, ln)
            end
            !isempty(d.message) &&
                println_wrapped_labeled(buf, "│     ", "", d.message, width)
            line = source_line_at(root, d)
            !isempty(line) && println_human_code_gutter(buf, width, d.anchor_line, line, d.span)
            println(buf, "│")
        end

        if total > limit
            omit = "│     ... (+$(total - limit) omitted)"
            for ln in wrap_prose_lines("", "", omit, width)
                println(buf, ln)
            end
        end

        footer = human_rule_footer(rule_id, d0.origin, cfg_label)
        for ln in wrap_prose_lines("", "", footer, width)
            println(buf, ln)
        end
        println(buf)
    end

    rule_hits = length(groups)
    status = result.exit_code == 0 ? "PASSED" : "FAILED"
    by_origin = human_summary_by_origin(groups)
    summary =
        "Summary: $(result.violation_count) violations across $rule_hits rules ($by_origin) — $status (exit $(result.exit_code))"
    for ln in wrap_prose_lines("", "", summary, width)
        println(buf, ln)
    end
    return String(take!(buf))
end
