function format_agent(
        result::CheckResult;
        max_hits::Int = 20,
        io::IO = stdout,
        output_width::Union{Nothing, Int} = nothing,
    )
    width = resolve_output_width(io; output_width = output_width)
    buf = IOBuffer()
    headline = "AGENTRULELINT $(result.exit_code == 0 ? "OK" : "FAIL") v$(pkgversion(AgentRuleLint)) pos=utf8-codepoint-1based violations=$(result.violation_count)"
    for ln in wrap_prose_lines("", "", headline, width)
        println(buf, ln)
    end
    println(buf)
    by_rule = Dict{String, Vector{Violation}}()
    for d in result.violations
        d.suppressed && continue
        d.expect_status == :fulfilled && continue
        push!(get!(by_rule, d.rule_id, Violation[]), d)
    end
    diag_order(v) = (v.path, v.span, v.rule_id)
    for (rid, ds) in sort(collect(by_rule); by = first)
        ds = sort(ds; by = diag_order)
        lvl = ds[1].level
        orig = origin_label(ds[1].origin)
        rule_line = "RULE $orig $rid level=$lvl count=$(length(ds))"
        for ln in wrap_prose_lines("", "", rule_line, width)
            println(buf, ln)
        end
        !isempty(ds[1].intent) &&
            println_wrapped_labeled(buf, "", "intent: ", ds[1].intent, width)
        !isempty(ds[1].do_not) &&
            println_wrapped_labeled(buf, "", "do_not: ", ds[1].do_not, width)
        limit = min(length(ds), max_hits)
        for i in 1:limit
            d = ds[i]
            sl = d.span
            loc = "$(d.path):$(sl.start_line):$(sl.start_col)-$(sl.end_line):$(sl.end_col)"
            hit_prefix = "HIT $loc | "
            cont_prefix = repeat(' ', visible_textwidth(hit_prefix))
            for ln in wrap_prose_lines(hit_prefix, cont_prefix, d.message, width)
                println(buf, ln)
            end
        end
        length(ds) > limit && begin
            for ln in wrap_prose_lines("", "", "... (+$(length(ds) - limit) omitted)", width)
                println(buf, ln)
            end
        end
        println(buf)
    end
    return String(take!(buf))
end
