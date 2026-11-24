const ID_PLACEHOLDER = Ref(0)
const STR_PLACEHOLDER = Ref(0)

function reset_anonymizer!()
    ID_PLACEHOLDER[] = 0
    return STR_PLACEHOLDER[] = 0
end

function anonymize_ident!(s::AbstractString)
    return Base.replace(
        s,
        r"\b[a-zA-Z_][a-zA-Z0-9_]*\b" => m -> begin
            if m == "end" || m == "function" || m == "if" || m == "using" || m == "module"
                return m
            end
            ID_PLACEHOLDER[] += 1
            return m[1] in ('x', 'X') ? "x$(ID_PLACEHOLDER[])" : "f$(ID_PLACEHOLDER[])"
        end,
    )
end

function anonymize_snippet(source::AbstractString)
    reset_anonymizer!()
    s = anonymize_ident!(source)
    STR_PLACEHOLDER[] = 0
    return Base.replace(
        s,
        r"\"([^\"]*)\"" => _ -> begin
            STR_PLACEHOLDER[] += 1
            return "\"s$(STR_PLACEHOLDER[])\""
        end,
    )
end

function _skeleton_walk!(parts::Vector{String}, node, pos)
    push!(parts, string(summary(node)))
    for (c, p) in _child_positions(node, pos)[1]
        JuliaSyntax.is_trivia(head(c)) && continue
        _skeleton_walk!(parts, c, p)
    end
    return nothing
end

function skeleton_ast_snippet(source::AbstractString)
    tree = parse_source(source)
    parts = String[]
    _skeleton_walk!(parts, tree, 1)
    return join(parts, "/")
end

function format_report(fingerprint::AbstractString, diagnostic::Violation, source::AbstractString)
    buf = IOBuffer()
    println(buf, "AgentRuleLint report v$(pkgversion(AgentRuleLint)) fingerprint=$fingerprint")
    println(buf, "rule_id=$(diagnostic.rule_id)")
    skel = skeleton_ast_snippet(source)
    lines = split(normalize_source(source), '\n')
    line =
        diagnostic.anchor_line <= length(lines) ? String(lines[diagnostic.anchor_line]) : String(source)
    anon = anonymize_snippet(line)
    println(buf, anon)
    println(buf, "pattern_hash=$(pattern_hash(skel))")
    return String(take!(buf))
end

function _explain_extra(spec::RuleSpec, key::Symbol)
    return get(spec.extra, key, "")
end

function format_explain_rule(spec::RuleSpec)
    anchor = _explain_extra(spec, :expect_anchor)
    example = _explain_extra(spec, :example)
    return """
    rule_id: $(spec.id)
    origin: $(origin_label(spec.origin))
    level: $(spec.level)

    intent:
    $(spec.intent)

    do_not:
    $(spec.do_not)

    expect_anchor:
    $(isempty(anchor) ? "N/A." : anchor)

    example:
    $(isempty(example) ? "N/A." : example)
    """
end

function format_explain_project_rule(pr::ProjectRule)
    rid = project_rule_id(pr)
    return """
    rule_id: $rid
    origin: [Project]
    level: $(pr.level)

    intent:
    $(pr.intent)

    do_not:
    $(pr.do_not)

    expect_anchor:
    When using expect-audit suppression, reference `$rid` in `# agentrulelint-expect:` (same placement rules as expect-audit).

    example:
    # agentrulelint-expect: $rid reason="documented"
    x = "forbidden_literal"
    """
end

function explain_rule_unknown(id::AbstractString; root::AbstractString = pwd())
    needle = String(strip(id))
    policy = resolve_policy(root)
    init_registry!(policy)
    if startswith(needle, "project/")
        short = needle[9:end]
        return !any(pr -> pr.id == short, policy.project_rules)
    end
    return !haskey(BUILTIN_RULES, needle)
end

function explain_rule(id::AbstractString; root::AbstractString = pwd())
    needle = String(strip(id))
    explain_rule_unknown(needle; root = root) &&
        throw(ArgumentError("unknown rule id: $needle"))
    policy = resolve_policy(root)
    init_registry!(policy)
    if startswith(needle, "project/")
        short = needle[9:end]
        for pr in policy.project_rules
            pr.id == short && return format_explain_project_rule(pr)
        end
        throw(ArgumentError("unknown rule id: $needle"))
    end
    spec = BUILTIN_RULES[needle]
    return format_explain_rule(spec)
end
