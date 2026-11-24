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

function _human_loc_styled(io::IO, loc::AbstractString)
    return emit_plain_or_styled(
        io,
        String(loc);
        bold = color_enabled(io),
    )
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
    ceilings = load_ceilings(root, policy)
    groups = violations_by_rule(active_violations(result.violations))
    max_hits = result.max_hits_per_rule
    for (rule_id, ds) in groups
        d0 = ds[1]
        label = origin_label(d0.origin)
        total = length(ds)
        ceiling = rule_violation_total(ceilings, rule_id)
        ceiling_s = ceiling > 0 ? string(ceiling) : "-"
        rid_s = _human_rule_id_styled(io, rule_id)
        lvl_s = _human_level_styled(io, d0.level)
        header = "$label $rid_s level=$lvl_s count=$total ceiling=$ceiling_s"
        for ln in wrap_prose_lines("", "", header, width)
            println(buf, ln)
        end
        !isempty(d0.intent) && println_wrapped_labeled(buf, "", "intent: ", d0.intent, width)
        !isempty(d0.do_not) && println_wrapped_labeled(buf, "", "do_not: ", d0.do_not, width)
        println(buf)
        limit = min(total, max_hits)
        for i in 1:limit
            d = ds[i]
            loc = format_span_loc(d)
            loc_out = _human_loc_styled(io, loc)
            for ln in wrap_prose_lines("", "", loc_out, width)
                println(buf, ln)
            end
            line = source_line_at(root, d)
            if !isempty(line)
                for ln in wrap_prose_lines("", "", line, width)
                    println(buf, ln)
                end
                ul = underline_for_span(line, d.span)
                !isempty(ul) && for ln in wrap_prose_lines("", "", ul, width)
                    println(buf, ln)
                end
            end
            println(buf)
        end
        if total > limit
            for ln in wrap_prose_lines("", "", "... (+$(total - limit) omitted)", width)
                println(buf, ln)
            end
            println(buf)
        end
        footer = "agentrulelint explain $rule_id"
        for ln in wrap_prose_lines("", "", footer, width)
            println(buf, ln)
        end
        println(buf)
    end
    rule_hits = length(groups)
    summary =
        "Summary: $(result.violation_count) violations, $rule_hits rules, exit $(result.exit_code)"
    for ln in wrap_prose_lines("", "", summary, width)
        println(buf, ln)
    end
    return String(take!(buf))
end
