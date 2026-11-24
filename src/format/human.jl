function _snippet_for_violation(root::AbstractString, d::Violation)
    path = joinpath(root, d.path)
    !isfile(path) && return ""
    source = normalize_source(read(path, String))
    lines = split(source, '\n')
    d.anchor_line > length(lines) && return ""
    line = lines[d.anchor_line]
    sc = min(d.span.start_col, length(line))
    ec = min(d.span.end_col, length(line))
    sc < 1 && (sc = 1)
    ec < sc && (ec = sc)
    chars = collect(eachindex(line))
    sc > length(chars) && return strip(line)
    ec = min(ec, length(chars))
    return strip(line[chars[sc]:chars[ec]])
end

function format_human(result::CheckResult; root::AbstractString = pwd())
    buf = IOBuffer()
    shown = Dict{String, Int}()
    omitted = Dict{String, Int}()
    max_hits = result.max_hits_per_rule
    println(buf, "AgentRuleLint v$(pkgversion(AgentRuleLint)) (pos: utf8-codepoint-1based)")
    println(buf)
    for d in result.violations
        d.suppressed && continue
        d.expect_status == :fulfilled && continue
        d.level == :allow && continue
        key = d.rule_id
        shown[key] = get(shown, key, 0) + 1
        if shown[key] > max_hits
            omitted[key] = get(omitted, key, 0) + 1
            continue
        end
        label = origin_label(d.origin)
        println(buf, "┌ Error: $label $(d.rule_id) [$(d.level)]")
        !isempty(d.intent) && println(buf, "│   intent: $(d.intent)")
        !isempty(d.do_not) && println(buf, "│   do_not: $(d.do_not)")
        println(buf, "│")
        sl = d.span
        println(buf, "│   $(d.path):$(sl.start_line):$(sl.start_col)-$(sl.end_line):$(sl.end_col)")
        println(buf, "│     $(d.message)")
        snip = _snippet_for_violation(root, d)
        !isempty(snip) && println(buf, "│     > $(snip)")
        println(buf, "└")
        println(buf)
    end
    for (rid, n) in sort(collect(omitted))
        println(buf, "... (+$n omitted) for rule $rid")
    end
    println(
        buf,
        "Summary: $(result.violation_count) violations, $(result.suppressed_count) suppressed — $(result.exit_code == 0 ? "PASSED" : "FAILED") (exit $(result.exit_code))",
    )
    return String(take!(buf))
end
