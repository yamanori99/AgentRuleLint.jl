const ID_PLACEHOLDER = Ref(0)
const STR_PLACEHOLDER = Ref(0)

function reset_anonymizer!()
    ID_PLACEHOLDER[] = 0
    return STR_PLACEHOLDER[] = 0
end

function anonymize_ident!(s::AbstractString)
    return replace(s, r"\b[a-zA-Z_][a-zA-Z0-9_]*\b") do m
        if m == "end" || m == "function" || m == "if"
            return m
        end
        ID_PLACEHOLDER[] += 1
        return m[1] in ('x', 'X') ? "x$(ID_PLACEHOLDER[])" : "f$(ID_PLACEHOLDER[])"
    end
end

function anonymize_snippet(source::AbstractString)
    reset_anonymizer!()
    s = anonymize_ident!(source)
    STR_PLACEHOLDER[] = 0
    return replace(s, r"\"([^\"]*)\"") do _
        STR_PLACEHOLDER[] += 1
        return "\"s$(STR_PLACEHOLDER[])\""
    end
end

function skeleton_ast_snippet(source::AbstractString)
    tree = parse_source(source)
    parts = String[]
    function walk(node)
        h = head_name(node)
        push!(parts, h)
        JuliaSyntax.is_leaf(node) && return
        for ch in JuliaSyntax.children(node)
            walk(ch)
        end
        return
    end
    walk(tree)
    return join(parts, "/")
end

function format_report(fingerprint::AbstractString, diagnostic::Diagnostic, source::AbstractString)
    buf = IOBuffer()
    header = Dict{String, Any}(
        "type" => "header",
        "jailint_version" => string(pkgversion(JAILint)),
        "julia_version" => string(VERSION),
        "parser" => parser_rev_string(),
        "position_encoding" => "utf8-codepoint-1based",
    )
    println(buf, _json_val(header))
    println(buf, _json_val(Dict("rule_id" => diagnostic.rule_id)))
    skel = skeleton_ast_snippet(source)
    anon = anonymize_snippet(source)
    println(
        buf,
        _json_val(
            Dict(
                "fingerprint" => fingerprint,
                "snippet" => anon,
                "pattern_hash" => pattern_hash(skel),
            ),
        ),
    )
    return String(take!(buf))
end

function explain_rule(id::AbstractString)
    id = String(id)
    if id == "JA004" || id == "expect-audit"
        return """
        JA004 expect-audit

        Anchor line: first non-blank code line after contiguous `# jailint-expect:` lines.

        Syntax: `# jailint-expect: <rule> reason="..."` (ASCII, standalone line only).

        Suppresses only diagnostics whose anchor_line matches that line.
        """
    elseif startswith(id, "JP:")
        return "Project rule $(id)"
    else
        return "Unknown rule id: $(id)"
    end
end
