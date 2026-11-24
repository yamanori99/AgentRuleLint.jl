function format_agent(result::CheckResult; max_hits::Int = 20)
    buf = IOBuffer()
    println(buf, "JAILINT $(result.exit_code == 0 ? "OK" : "FAIL") v$(pkgversion(JAILint)) pos=utf8-codepoint-1based violations=$(result.violation_count)")
    println(buf)
    by_rule = Dict{String, Vector{Diagnostic}}()
    for d in result.diagnostics
        d.suppressed && continue
        d.expect_status == :fulfilled && continue
        push!(get!(by_rule, d.rule_id, Diagnostic[]), d)
    end
    for (rid, ds) in sort(collect(by_rule))
        lvl = ds[1].level
        orig = origin_label(ds[1].origin)
        println(buf, "RULE $orig $rid level=$lvl count=$(length(ds))")
        !isempty(ds[1].intent) && println(buf, "intent: $(ds[1].intent)")
        !isempty(ds[1].do_not) && println(buf, "do_not: $(ds[1].do_not)")
        limit = min(length(ds), max_hits)
        for i in 1:limit
            d = ds[i]
            sl = d.span
            println(buf, "HIT $(d.path):$(sl.start_line):$(sl.start_col)-$(sl.end_line):$(sl.end_col) | $(d.message)")
        end
        length(ds) > limit && println(buf, "... (+$(length(ds) - limit) omitted)")
        println(buf)
    end
    return String(take!(buf))
end
