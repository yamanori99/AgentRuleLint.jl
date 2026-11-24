# uses normalize_source, standalone_comment_lines, span_for_line from SyntaxAdapter scope

const EXPECT_PREFIX = "jailint-expect:"
const JAILINT_PREFIX = "jailint"

const _MALFORMED_EXPECT = (
    status = :malformed,
    rule_ref = "",
    reason = "",
    message = "",
)

function parse_expect_body(body::AbstractString)
    body = strip(body)
    startswith(body, EXPECT_PREFIX) || return nothing
    rest = strip(body[(length(EXPECT_PREFIX) + 1):end])
    isempty(rest) &&
        return (; _MALFORMED_EXPECT..., message = "empty expect")
    if match(r"^\S+\s+reason=\"\"\s*$", rest) !== nothing
        return (; _MALFORMED_EXPECT..., message = "empty reason")
    end
    m = match(r"^(\S+)\s+reason=\"([^\"]+)\"$", rest)
    m === nothing && return (; _MALFORMED_EXPECT..., message = "missing reason=\"...\"")
    rule_ref = m.captures[1]
    reason = m.captures[2]
    rule_ref === nothing && return (; _MALFORMED_EXPECT..., message = "missing rule id")
    reason === nothing && return (; _MALFORMED_EXPECT..., message = "missing reason")
    isempty(strip(String(reason))) && return (; _MALFORMED_EXPECT..., message = "empty reason")
    return (
        status = :ok,
        rule_ref = String(rule_ref),
        reason = String(reason),
        message = "",
    )
end

function scan_block_comments(source::AbstractString)
    errs = Tuple{Int, String}[]
    pattern = r"#=([\s\S]*?)=#"
    for m in eachmatch(pattern, source)
        inner = m.captures[1]
        inner === nothing && continue
        occursin("jailint-expect:", inner) || continue
        line = line_number_at_byte(source, m.offset)
        push!(errs, (line, "block comment expect forbidden"))
    end
    return errs
end

function detect_inline_expect_trailing(source::AbstractString)
    diags = Vector{Tuple{Int, String}}()
    for (i, line) in enumerate(split(normalize_source(source), '\n'))
        pos = findfirst("# jailint-expect:", line)
        pos === nothing && continue
        cut = pos isa AbstractRange ? first(pos) : pos
        cut = cut isa Integer ? cut : first(cut)
        code = cut > 1 ? strip(line[1:prevind(line, cut)]) : ""
        !isempty(code) && push!(diags, (i, "trailing inline expect"))
    end
    return diags
end

function detect_malformed_jailint(source::AbstractString)
    src = normalize_source(source)
    diags = Vector{Tuple{Int, String}}()
    standalone = standalone_comment_lines(src)
    for (i, line) in enumerate(split(src, '\n'))
        stripped = strip(line)
        if occursin("jailint-expect:", line)
            idx = findfirst("# jailint-expect:", line)
            if idx !== nothing
                cut = idx isa AbstractRange ? first(idx) : idx
                cut = cut isa Integer ? cut : first(cut)
                code = cut > 1 ? strip(line[1:prevind(line, cut)]) : ""
                !isempty(code) && push!(diags, (i, "trailing inline expect"))
            end
        end
        startswith(stripped, "#") || continue
        body = strip(stripped[2:end])
        occursin(JAILINT_PREFIX, body) || continue
        if haskey(standalone, i)
            if startswith(body, "jailint-expect:")
                parsed = parse_expect_body(body)
                parsed === nothing && push!(diags, (i, "malformed expect"))
                parsed !== nothing && parsed.status == :malformed &&
                    push!(diags, (i, String(parsed.message)))
            elseif startswith(body, "jailint")
                push!(diags, (i, "malformed # jailint* directive"))
            end
        end
    end
    return diags
end

function extract_expect_lines(source::AbstractString)
    source = normalize_source(source)
    comments = standalone_comment_lines(source)
    expects = ExpectLine[]
    for (line_no, body) in comments
        startswith(body, EXPECT_PREFIX) || continue
        parsed = parse_expect_body(body)
        parsed === nothing && continue
        parsed.status == :malformed && continue
        parsed.status != :ok && continue
        push!(expects, ExpectLine(line_no, parsed.rule_ref, parsed.reason, body))
    end
    return expects
end

function contiguous_expect_groups(expects::Vector{ExpectLine})
    isempty(expects) && return Vector{Vector{ExpectLine}}()
    sorted = sort(expects; by = e -> e.line)
    groups = Vector{ExpectLine}[]
    cur = ExpectLine[sorted[1]]
    for i in 2:length(sorted)
        if sorted[i].line == sorted[i - 1].line + 1
            push!(cur, sorted[i])
        else
            push!(groups, cur)
            cur = ExpectLine[sorted[i]]
        end
    end
    push!(groups, cur)
    return groups
end

function anchor_after_group(group::Vector{ExpectLine}, source::AbstractString)
    anchor, mismatch = resolve_expect_anchor_line(group, source)
    mismatch && return 0
    return anchor
end

function _push_expect_violation!(
        diags::Vector{Violation},
        msg::String,
        rule,
        path::String,
        source::AbstractString,
        line_no::Int,
        lvl::Symbol,
    )
    _, span = span_for_line(source, line_no)
    intent = rule === nothing ? "" : rule.intent
    do_not = rule === nothing ? "" : rule.do_not
    push!(
        diags,
        Violation(
            "expect-audit",
            :jailint,
            lvl,
            path,
            span,
            line_no,
            diagnostic_fingerprint("expect-audit", path, line_no, msg, 1),
            :unfulfilled,
            false,
            msg,
            intent,
            do_not,
        ),
    )
    return
end


function apply_expect_suppression!(diags::Vector{Violation}, expects::Vector{ExpectLine}, source::AbstractString)
    groups = contiguous_expect_groups(expects)
    anchors = Dict{Int, Vector{ExpectLine}}()
    for g in groups
        al = anchor_after_group(g, source)
        al > 0 && (anchors[al] = g)
    end
    used_expect = Set{Int}()
    for (i, d) in enumerate(diags)
        d.suppressed && continue
        anchor = d.anchor_line
        group = get(anchors, anchor, nothing)
        group === nothing && continue
        for ex in group
            rule_ref_matches(ex.rule_ref, d.rule_id) || continue
            diags[i] = Violation(
                d.rule_id,
                d.origin,
                d.level,
                d.path,
                d.span,
                d.anchor_line,
                d.fingerprint,
                :fulfilled,
                true,
                d.message,
                d.intent,
                d.do_not,
            )
            push!(used_expect, ex.line)
            break
        end
    end
    return used_expect
end

function expect_audit_diagnostics(fc::FileContext, policy::PolicyBundle)
    source = fc.parsed.normalized
    diags = Violation[]
    rule = get(policy.rules, "expect-audit", nothing)
    lvl = rule === nothing ? :forbid : rule.level
    path = fc.parsed.path

    seen = Set{Tuple{Int, String}}()
    for (line_no, msg) in detect_malformed_jailint(source)
        key = (line_no, msg)
        key in seen && continue
        push!(seen, key)
        _push_expect_violation!(diags, msg, rule, path, source, line_no, lvl)
    end

    for (line_no, msg) in scan_block_comments(source)
        key = (line_no, msg)
        key in seen && continue
        push!(seen, key)
        _push_expect_violation!(diags, msg, rule, path, source, line_no, lvl)
    end

    runic_regions = runic_off_regions(source)
    call_arg_lines = multiline_call_interior_lines(source)
    lines = split(source, '\n')

    for ex in fc.expects
        if line_in_runic_off_region(ex.line, runic_regions)
            msg = "expect inside runic:off region forbidden"
            _push_expect_violation!(diags, msg, rule, path, source, ex.line, lvl)
        end
        ex.line in call_arg_lines && _push_expect_violation!(
            diags,
            "expect inside multiline call arguments",
            rule,
            path,
            source,
            ex.line,
            :warn,
        )
    end

    groups = contiguous_expect_groups(fc.expects)
    for g in groups
        last_e = maximum(e.line for e in g)
        anchor, mismatch = resolve_expect_anchor_line(g, source)
        code_li = first_code_line_after(source, last_e)
        if code_li > 0
            code = code_prefix_on_line(lines[code_li])
            line_is_catch_header(code) &&
                _push_expect_violation!(diags, "expect forbidden above catch", rule, path, source, last_e, lvl)
        end
        mismatch && code_li > 0 && begin
            for ex in g
                _push_expect_violation!(
                    diags,
                    "expect not anchored to rule target syntax",
                    rule,
                    path,
                    source,
                    ex.line,
                    lvl,
                )
            end
        end
        anchor == 0 && continue
        if anchor > last_e + 1
            for ex in g
                _push_expect_violation!(
                    diags,
                    "blank line breaking expect attachment (unused)",
                    rule,
                    path,
                    source,
                    ex.line,
                    lvl,
                )
            end
        end
    end

    return diags
end

function unused_expect_diagnostics(expects::Vector{ExpectLine}, used::Set{Int}, fc::FileContext, policy::PolicyBundle)
    rule = get(policy.rules, "expect-audit", nothing)
    lvl = rule === nothing ? :forbid : rule.level
    intent = rule === nothing ? "" : rule.intent
    do_not = rule === nothing ? "" : rule.do_not
    source = fc.parsed.normalized
    path = fc.parsed.path
    diags = Violation[]
    for ex in expects
        ex.line in used && continue
        msg = "unused expect"
        _, span = span_for_line(source, ex.line)
        push!(
            diags,
            Violation(
                "expect-audit",
                :jailint,
                lvl,
                path,
                span,
                ex.line,
                diagnostic_fingerprint("expect-audit", path, ex.line, msg, 1),
                :unfulfilled,
                false,
                msg,
                intent,
                do_not,
            ),
        )
    end
    return diags
end

function forbid_rule_suppression_attempt(expects::Vector{ExpectLine}, policy::PolicyBundle, fc::FileContext)
    diags = Violation[]
    rule = get(policy.rules, "expect-audit", nothing)
    lvl = rule === nothing ? :forbid : rule.level
    source = fc.parsed.normalized
    path = fc.parsed.path
    for ex in expects
        is_forbid_rule(policy, ex.rule_ref) || continue
        _, span = span_for_line(source, ex.line)
        msg = "forbid rule suppression"
        push!(
            diags,
            Violation(
                "expect-audit",
                :jailint,
                lvl,
                path,
                span,
                ex.line,
                diagnostic_fingerprint("expect-audit", path, ex.line, msg, 1),
                :unfulfilled,
                false,
                msg,
                rule === nothing ? "" : rule.intent,
                rule === nothing ? "" : rule.do_not,
            ),
        )
    end
    return diags
end
