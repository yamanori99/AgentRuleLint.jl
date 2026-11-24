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

function format_human(
        result::CheckResult;
        root::AbstractString = pwd(),
        io::IO = stdout,
        output_width::Union{Nothing, Int} = nothing,
    )
    width = resolve_output_width(io; output_width = output_width)
    buf = IOBuffer()
    shown = Dict{String, Int}()
    omitted = Dict{String, Int}()
    max_hits = result.max_hits_per_rule
    for ln in wrap_prose_lines("", "", "JAILint v$(pkgversion(JAILint)) (pos: utf8-codepoint-1based)", width)
        println(buf, ln)
    end
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
        header = "┌ Error: $label $(d.rule_id) [$(d.level)]"
        for ln in wrap_prose_lines("", "", header, width)
            println(buf, ln)
        end
        !isempty(d.intent) &&
            println_wrapped_labeled(buf, "│   ", "intent: ", d.intent, width)
        !isempty(d.do_not) &&
            println_wrapped_labeled(buf, "│   ", "do_not: ", d.do_not, width)
        println(buf, "│")
        sl = d.span
        println(buf, "│   $(d.path):$(sl.start_line):$(sl.start_col)-$(sl.end_line):$(sl.end_col)")
        println_wrapped_labeled(buf, "│     ", "", d.message, width)
        snip = _snippet_for_violation(root, d)
        !isempty(snip) && println(buf, truncate_quoted_line("│     > ", snip, width))
        println(buf, "└")
        println(buf)
    end
    for (rid, n) in sort(collect(omitted))
        for ln in wrap_prose_lines("", "", "... (+$n omitted) for rule $rid", width)
            println(buf, ln)
        end
    end
    summary = "Summary: $(result.violation_count) violations, $(result.suppressed_count) suppressed — $(result.exit_code == 0 ? "PASSED" : "FAILED") (exit $(result.exit_code))"
    for ln in wrap_prose_lines("", "", summary, width)
        println(buf, ln)
    end
    return String(take!(buf))
end
