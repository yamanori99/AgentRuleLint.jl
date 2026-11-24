using StyledStrings

function format_human(result::CheckResult)
    buf = IOBuffer()
    println(buf, "JAILint v$(pkgversion(JAILint)) (pos: utf8-codepoint-1based)")
    println(buf)
    for d in result.diagnostics
        d.suppressed && continue
        d.expect_status == :fulfilled && continue
        key = d.rule_id
        shown[key] = get(shown, key, 0) + 1
        label = origin_label(d.origin)
        println(buf, "┌ Error: $label $(d.rule_id) [$(d.level)]")
        !isempty(d.intent) && println(buf, "│   intent: $(d.intent)")
        !isempty(d.do_not) && println(buf, "│   do_not: $(d.do_not)")
        println(buf, "│")
        sl = d.span
        println(buf, "│   $(d.path):$(sl.start_line):$(sl.start_col)-$(sl.end_line):$(sl.end_col)")
        println(buf, "│     $(d.message)")
        println(buf, "└ @ $(label)")
        println(buf)
    end
    println(
        buf,
        "Summary: $(result.violation_count) violations, $(result.suppressed_count) suppressed — $(result.exit_code == 0 ? "PASSED" : "FAILED") (exit $(result.exit_code))",
    )
    return String(take!(buf))
end
