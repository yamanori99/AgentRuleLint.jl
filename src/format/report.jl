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
    header = Dict{String, Any}(
        "type" => "header",
        "agentrulelint_version" => string(pkgversion(AgentRuleLint)),
        "julia_version" => string(VERSION),
        "parser" => parser_rev_string(),
        "position_encoding" => "utf8-codepoint-1based",
    )
    println(buf, _json_val(header))
    println(buf, _json_val(Dict("rule_id" => diagnostic.rule_id)))
    skel = skeleton_ast_snippet(source)
    lines = split(normalize_source(source), '\n')
    line =
        diagnostic.anchor_line <= length(lines) ? String(lines[diagnostic.anchor_line]) : String(source)
    anon = anonymize_snippet(line)
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
    if id == "expect-audit"
        return """
        expect-audit

        Anchor line: first non-blank code line after contiguous `# agentrulelint-expect:` lines
        that matches the target syntax kind for the referenced rule (e.g. `try`, `@eval`, `@test*`).

        Syntax: `# agentrulelint-expect: <rule-id> reason="..."` (ASCII, standalone line only; non-empty reason).

        Suppresses only violations whose anchor_line matches that line.
        Expects are forbidden above `catch`, inside `# runic: off` regions, inside multiline
        call arguments, and with blank lines before the anchor. Forbidden placements do not
        suppress violations. Multiline-call placement uses the same forbid level as other
        expect-audit integrity findings.
        """
    elseif id == "silent-catch"
        return """
        silent-catch

        Anchor line: the `try` keyword line of the `try`/`catch` (or `try`/`catch`/`finally`) expression.

        Flags catch-all handlers whose body does not rethrow or throw on unhandled paths: empty catch,
        assignments or `nothing` only, log-only handlers, and `if` branches without a propagating `else`.

        Legitimate patterns include `e isa T || rethrow()`, `if e isa T ... else rethrow() end`,
        unconditional `rethrow()` / `throw(...)`, and `err isa InterruptException && rethrow()`
        followed by a typed `throw`.

        Configure whether `@warn ... exception=...` alone counts as handling via
        `[rules.silent-catch]` `warn_counts_as_handling` (default: false).
        """
    elseif id == "protected-paths"
        return """
        protected-paths

        Group: integrity. Level: forbid (no inline expects).

        Runs only with `--diff <base>`. Reports nothing on a full-tree `check` without `--diff`.

        Auto-protected paths include `.AgentRuleLintConfig.toml`, `.agentrulelint/**`
        (except `.agentrulelint/ceilings.toml` when the diff is monotonic non-increasing),
        `.JETLSConfig.toml`, `Manifest*.toml`, `JuliaManifest.toml`, `LocalPreferences.toml`,
        and every repo-relative `Project.toml`.

        `project_toml_policy = "semantic"` (default) allows adding `[deps]` entries and `[compat]`
        for newly added deps. Any change to `[sources]` or `[workspace]`, compat removal, or any
        compat string change (loosening is any non-identical string; no semver reasoning in 0.1.0),
        or any other top-level key change is a violation.

        Declared `paths = [{ glob = "...", reason = "..." }]` under `[rules.protected-paths]` use
        project-rule path-glob syntax; the reason appears in the message.

        Missing or unparsable TOML on either side of a compared change fails closed (exit 2).

        Integrity level: `protected-paths`, `ceiling-ratchet`, and `scope-paths` must always use
        `level = "forbid"` in config. Any other level is a ConfigError (exit 2). Rename or copy
        of a protected path is never semantically exempt (including Project.toml and ceilings.toml).
        """
    elseif startswith(id, "project/")
        return "Project rule $(id) (declared under [[project_rules]] as id without prefix)."
    else
        specs = (
            "protected-paths" => "forbid edits to protected policy and workflow paths.",
            "scope-paths" => "enforce trusted path allowlists.",
            "ceiling-ratchet" => "keep violation/expect ceilings monotonic.",
            "manifest-sync" => "tracked Manifest must match Project.toml.",
            "shell-safety/process-pattern" => "preset: hazardous shell / Cmd patterns.",
            "test-integrity" => "detect hollow or weakened tests.",
            "unsafe-boundary" => "flag eval, ccall, and unsafe_* at boundaries.",
        )
        for (slug, blurb) in specs
            id == slug && return "$slug — $blurb (planned built-in / preset)."
        end
        return "Unknown rule id: $(id)"
    end
end
