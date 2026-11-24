# uses normalize_source, standalone_comment_lines, span_for_line from SyntaxAdapter scope

const EXPECT_PREFIX = "jailint-expect:"
const JAILINT_PREFIX = "jailint"

function parse_expect_body(body::AbstractString)
    body = strip(body)
    startswith(body, EXPECT_PREFIX) || return nothing
    rest = strip(body[length(EXPECT_PREFIX):end])
    isempty(rest) && return (:malformed, "empty expect")
    parts = split(rest, r"\s+", limit = 2)
    rule_ref = strip(parts[1])
    reason = ""
    if length(parts) >= 2
        r = strip(parts[2])
        m = match(r"^reason=\"(.*)\"$"s, r)
        m === nothing && return (:malformed, "missing reason=\"...\"")
        reason = m.captures[1]
    else
        return (:malformed, "missing reason=\"...\"")
    end
    return (:ok, rule_ref, reason)
end

function scan_block_comments(source::AbstractString)
    errs = Tuple{Int, String}[]
    pattern = r"#=([\s\S]*?)=#"
    for m in eachmatch(pattern, source)
        inner = m.captures[1]
        occursin("jailint-expect:", inner) &&
            push!(errs, (0, "block comment expect forbidden"))
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
        code = cut > 1 ? strip(line[1:prevind(line, cut)]) : strip(line)
        !isempty(code) && push!(diags, (i, "trailing inline expect"))
    end
    return diags
end

function detect_malformed_jailint(source::AbstractString)
    diags = Vector{Tuple{Int, String}}()
    for (i, line) in enumerate(split(normalize_source(source), '\n'))
        stripped = strip(line)
        startswith(stripped, "#") || continue
        body = strip(stripped[2:end])
        occursin(JAILINT_PREFIX, body) || continue
        if startswith(body, "jailint-expect:")
            parsed = parse_expect_body(body)
            parsed === nothing && push!(diags, (i, "malformed expect"))
            parsed isa Tuple && parsed[1] == :malformed &&
                push!(diags, (i, parsed[2]))
        elseif startswith(body, "jailint") && !startswith(body, EXPECT_PREFIX)
            # other jailint* on standalone line without valid expect
            idx = findfirst('#', line)
            code_before = idx === nothing ? line : line[1:prevind(line, idx)]
            isempty(strip(code_before)) || continue
        end
        m = match(r"(?i)#.*\bjailint\b", line)
        if m !== nothing && occursin("jailint-expect:", line)
            code = strip(split(line, "# jailint-expect:")[1])
            !isempty(code) && push!(diags, (i, "trailing inline expect"))
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
        if parsed[1] == :malformed
            continue
        end
        _, rule_ref, reason = parsed
        push!(expects, ExpectLine(line_no, rule_ref, reason, body))
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
    last_expect = maximum(e.line for e in group)
    lines = split(source, '\n')
    for li in (last_expect + 1):length(lines)
        isempty(strip(lines[li])) && continue
        return li
    end
    return 0
end

function rule_ref_matches(rule_ref::String, diagnostic_rule_id::String)
    rule_ref == diagnostic_rule_id && return true
    rule_ref == "JA004" && diagnostic_rule_id == "JA004" && return true
    rule_ref == "expect-audit" && diagnostic_rule_id == "JA004" && return true
    startswith(diagnostic_rule_id, "JP:") && rule_ref == diagnostic_rule_id[4:end] && return true
    startswith(diagnostic_rule_id, "JP:") && rule_ref == diagnostic_rule_id && return true
    rule_ref == diagnostic_rule_id && return true
    return false
end

function apply_expect_suppression!(diags::Vector{Diagnostic}, expects::Vector{ExpectLine}, source::AbstractString)
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
            diags[i] = Diagnostic(
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
    diags = Diagnostic[]
    rule = get(policy.rules, "expect-audit", nothing)
    lvl = rule === nothing ? :forbid : rule.level
    intent = rule === nothing ? "" : rule.intent
    do_not = rule === nothing ? "" : rule.do_not
    path = fc.parsed.path

    for (line_no, msg) in detect_inline_expect_trailing(source)
        sp, _, span = span_for_line(source, line_no)
        fp = diagnostic_fingerprint("JA004", path, line_no, msg, 1)
        push!(
            diags,
            Diagnostic("JA004", :jailint, lvl, path, span, line_no, fp, :unfulfilled, false, msg, intent, do_not),
        )
    end

    comments = standalone_comment_lines(source)
    for (line_no, body) in comments
        occursin(JAILINT_PREFIX, body) || continue
        if startswith(body, "jailint") && !startswith(body, EXPECT_PREFIX)
            msg = "malformed # jailint* directive"
            _, _, span = span_for_line(source, line_no)
            push!(
                diags,
                Diagnostic(
                    "JA004",
                    :jailint,
                    lvl,
                    path,
                    span,
                    line_no,
                    diagnostic_fingerprint("JA004", path, line_no, msg, 1),
                    :unfulfilled,
                    false,
                    msg,
                    intent,
                    do_not,
                ),
            )
        elseif startswith(body, EXPECT_PREFIX)
            parsed = parse_expect_body(body)
            if parsed === nothing || (parsed isa Tuple && parsed[1] == :malformed)
                msg = parsed isa Tuple ? parsed[2] : "malformed expect"
                _, _, span = span_for_line(source, line_no)
                push!(
                    diags,
                    Diagnostic(
                        "JA004",
                        :jailint,
                        lvl,
                        path,
                        span,
                        line_no,
                        diagnostic_fingerprint("JA004", path, line_no, msg, 1),
                        :unfulfilled,
                        false,
                        msg,
                        intent,
                        do_not,
                    ),
                )
            end
        end
    end

    for (_, msg) in scan_block_comments(source)
        line_no = 1
        _, _, span = span_for_line(source, line_no)
        push!(
            diags,
            Diagnostic(
                "JA004",
                :jailint,
                lvl,
                path,
                span,
                line_no,
                diagnostic_fingerprint("JA004", path, line_no, msg, 1),
                :unfulfilled,
                false,
                msg,
                intent,
                do_not,
            ),
        )
    end

    # blank line breaking attachment -> unused expect (fail-closed)
    groups = contiguous_expect_groups(fc.expects)
    for g in groups
        anchor = anchor_after_group(g, source)
        anchor == 0 && continue
        # check blank line between last expect and anchor
        last_e = maximum(e.line for e in g)
        if anchor > last_e + 1
            for ex in g
                _, _, span = span_for_line(source, ex.line)
                msg = "blank line breaking expect attachment (unused)"
                push!(
                    diags,
                    Diagnostic(
                        "JA004",
                        :jailint,
                        lvl,
                        path,
                        span,
                        ex.line,
                        diagnostic_fingerprint("JA004", path, ex.line, msg, 1),
                        :unfulfilled,
                        false,
                        msg,
                        intent,
                        do_not,
                    ),
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
    diags = Diagnostic[]
    for ex in expects
        ex.line in used && continue
        msg = "unused expect"
        _, _, span = span_for_line(source, ex.line)
        push!(
            diags,
            Diagnostic(
                "JA004",
                :jailint,
                lvl,
                path,
                span,
                ex.line,
                diagnostic_fingerprint("JA004", path, ex.line, msg, 1),
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
    diags = Diagnostic[]
    rule = get(policy.rules, "expect-audit", nothing)
    lvl = rule === nothing ? :forbid : rule.level
    source = fc.parsed.normalized
    path = fc.parsed.path
    for ex in expects
        rid = ex.rule_ref
        for (_, r) in policy.rules
            (r.code == rid || r.id == rid) || continue
            r.level == :forbid || continue
            _, _, span = span_for_line(source, ex.line)
            msg = "forbid rule suppression"
            push!(
                diags,
                Diagnostic(
                    "JA004",
                    :jailint,
                    lvl,
                    path,
                    span,
                    ex.line,
                    diagnostic_fingerprint("JA004", path, ex.line, msg, 1),
                    :unfulfilled,
                    false,
                    msg,
                    rule.intent,
                    rule.do_not,
                ),
            )
        end
    end
    return diags
end
