function format_agent(
        result::CheckResult;
        root::AbstractString = pwd(),
        max_hits::Union{Nothing, Int} = nothing,
        io::IO = stdout,
        output_width::Union{Nothing, Int} = nothing,
        _agentrulelint_version::Union{Nothing, AbstractString} = nothing, # test-only: override the displayed version (see test_output_goldens.jl)
    )
    width = resolve_output_width(io; output_width = output_width)
    hit_cap = something(max_hits, result.max_hits_per_rule)
    buf = IOBuffer()
    ceilings = result.ceilings
    base = config_source_base_label(result.config_source)
    groups = violations_by_rule(active_violations(result.violations))
    rule_hits = length(groups)
    status = result.exit_code == 0 ? "OK" : "FAIL"
    ver = something(_agentrulelint_version, string(AGENTRULELINT_VERSION))
    headline =
        "AGENTRULELINT $status v$ver base=$base pos=utf8-codepoint-1based violations=$(result.violation_count) rules=$rule_hits"
    println(buf, headline)
    println(buf)
    for (rid, all_ds) in groups
        lvl = all_ds[1].level
        orig = origin_label(all_ds[1].origin)
        total = length(all_ds)
        ceiling = rule_violation_total(ceilings, rid)
        ceiling_s = ceiling > 0 ? string(ceiling) : "-"
        rule_line = "RULE $orig $rid level=$lvl count=$total ceiling=$ceiling_s"
        for ln in wrap_prose_lines("", "", rule_line, width)
            println(buf, ln)
        end
        !isempty(all_ds[1].intent) &&
            println_wrapped_labeled(buf, "", "intent: ", all_ds[1].intent, width)
        !isempty(all_ds[1].do_not) &&
            println_wrapped_labeled(buf, "", "do_not: ", all_ds[1].do_not, width)
        limit = min(total, hit_cap)
        for i in 1:limit
            d = all_ds[i]
            snip = snippet_for_violation(root, d)
            loc = format_span_loc(d)
            hit_prefix = "HIT $loc | "
            cont_prefix = repeat(' ', visible_textwidth(hit_prefix))
            body = isempty(snip) ? d.message : snip
            for ln in wrap_prose_lines(hit_prefix, cont_prefix, body, width)
                println(buf, ln)
            end
        end
        total > limit && begin
            for ln in wrap_prose_lines("", "", "... (+$(total - limit) omitted)", width)
                println(buf, ln)
            end
        end
        println(buf)
    end
    return String(take!(buf))
end
