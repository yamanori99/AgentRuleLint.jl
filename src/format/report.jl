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

function _explain_registry_blurb(id::String)
    specs = Dict(
        "protected-paths" => (
            "Block edits to protected policy and workflow paths.",
            "Do not modify `.AgentRuleLintConfig.toml`, workflows, or manifests without review.",
            :forbid,
            :agentrulelint,
            "",
            "N/A (integrity guard on path diffs).",
        ),
        "scope-paths" => (
            "Enforce trusted path allowlists for agent edits.",
            "Do not touch paths outside configured allowlists.",
            :forbid,
            :agentrulelint,
            "",
            "N/A (diff scope only).",
        ),
        "ceiling-ratchet" => (
            "Keep violation ceilings monotonic.",
            "Do not ratchet ceilings upward without review.",
            :forbid,
            :agentrulelint,
            "",
            "Compared against `.agentrulelint/ceilings.toml`.",
        ),
        "manifest-sync" => (
            "Tracked Manifest must match Project.toml.",
            "Do not commit a stale Manifest.",
            :forbid,
            :agentrulelint,
            "",
            "N/A.",
        ),
        "shell-safety/process-pattern" => (
            "Flag hazardous shell / Cmd patterns (preset).",
            "Do not spawn unreviewed shell pipelines.",
            :deny,
            :preset,
            "",
            "# agentrulelint-expect: shell-safety/process-pattern reason=\"...\" on the following line.",
        ),
        "silent-catch" => (
            "Detect swallowed exceptions.",
            "Do not use empty catch blocks without expects.",
            :deny,
            :agentrulelint,
            "",
            "# agentrulelint-expect: silent-catch reason=\"...\" on the anchor line.",
        ),
        "test-integrity" => (
            "Detect hollow or weakened tests.",
            "Do not delete assertions to silence CI.",
            :forbid,
            :agentrulelint,
            "",
            "N/A.",
        ),
        "unsafe-boundary" => (
            "Flag eval, ccall, and unsafe_* at boundaries.",
            "Do not bypass sandboxing via reflection.",
            :deny,
            :agentrulelint,
            "",
            "# agentrulelint-expect: unsafe-boundary reason=\"...\"",
        ),
    )
    return get(specs, id, nothing)
end

function _known_rule_ids(root::AbstractString)
    policy = resolve_policy(root)
    init_registry!(policy)
    ids = String[]
    for (id, _) in policy.rules
        push!(ids, id)
    end
    for pr in policy.project_rules
        push!(ids, project_rule_id(pr))
    end
    for id in keys(BUILTIN_RULES)
        id in ids || push!(ids, id)
    end
    blurb_ids = String[
        "protected-paths",
        "scope-paths",
        "ceiling-ratchet",
        "manifest-sync",
        "shell-safety/process-pattern",
        "silent-catch",
        "test-integrity",
        "unsafe-boundary",
    ]
    for id in blurb_ids
        id in ids || push!(ids, id)
    end
    return sort(unique(ids))
end

function explain_rule_unknown(id::AbstractString; root::AbstractString = pwd())
    needle = String(strip(id))
    return needle ∉ _known_rule_ids(root)
end

function explain_rule(id::AbstractString; root::AbstractString = pwd())
    needle = String(strip(id))
    explain_rule_unknown(needle; root = root) &&
        throw(ArgumentError("unknown rule id: $needle"))
    policy = resolve_policy(root)
    init_registry!(policy)
    if needle == "expect-audit"
        spec = get(policy.rules, "expect-audit", BUILTIN_RULES["expect-audit"])
        return """
        rule_id: expect-audit
        origin: $(origin_label(spec.origin))
        level: $(spec.level)

        intent:
        $(spec.intent)

        do_not:
        $(spec.do_not)

        expect_anchor:
        First non-blank code line after contiguous `# agentrulelint-expect:` lines that matches the target syntax kind.

        example:
        # agentrulelint-expect: expect-audit reason="documented suppression"
        @eval :ok
        """
    end
    if startswith(needle, "project/")
        short = needle[9:end]
        for pr in policy.project_rules
            pr.id == short || continue
            return """
            rule_id: $(project_rule_id(pr))
            origin: [Project]
            level: $(pr.level)

            intent:
            $(pr.intent)

            do_not:
            $(pr.do_not)

            expect_anchor:
            Same as expect-audit when referenced by rule id $(project_rule_id(pr)).

            example:
            x = "forbidden_literal"  # matched when configured in forbid_literals
            """
        end
        throw(ArgumentError("unknown rule id: $needle"))
    end
    if haskey(policy.rules, needle)
        spec = policy.rules[needle]
        blurb = _explain_registry_blurb(needle)
        anchor = blurb === nothing ? "N/A." : blurb[6]
        example = needle == "expect-audit" ? "" : blurb === nothing ? "N/A." : blurb[6]
        return """
        rule_id: $needle
        origin: $(origin_label(spec.origin))
        level: $(spec.level)

        intent:
        $(spec.intent)

        do_not:
        $(spec.do_not)

        expect_anchor:
        $anchor

        example:
        $example
        """
    end
    blurb = _explain_registry_blurb(needle)
    blurb === nothing && throw(ArgumentError("unknown rule id: $needle"))
    return """
    rule_id: $needle
    origin: $(origin_label(blurb[4]))
    level: $(blurb[3])

    intent:
    $(blurb[1])

    do_not:
    $(blurb[2])

    expect_anchor:
    $(blurb[6])

    example:
    $(blurb[6])
    """
end
