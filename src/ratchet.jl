# Ceiling ratchet: monotonic per-(rule, path) violation and expect counts (fail-closed).

const CEILING_VIOLATIONS_PREFIX = "violations"
const CEILING_EXPECTS_PREFIX = "expects"
const CEILING_RATCHET_RULE = "ceiling-ratchet"

function _ceilings_path(root::AbstractString)
    return joinpath(abspath(root), CEILINGS_REL)
end

function _known_rule_ids(policy::PolicyBundle)
    out = Set{String}()
    for (_, r) in policy.rules
        push!(out, r.id)
    end
    for pr in policy.project_rules
        push!(out, project_rule_id(pr))
    end
    return out
end

function _parse_ceiling_table(raw, _prefix::String, label::String)
    raw isa Dict || throw(ConfigError("malformed ceilings: $label must be a table"))
    outer = Dict{String, Dict{String, Int}}()
    for (rid, paths) in raw
        sid = String(rid)
        paths isa Dict || throw(ConfigError("malformed ceilings: $label.$sid must be a table"))
        inner = Dict{String, Int}()
        for (p, c) in paths
            sp = String(p)
            c isa Integer || throw(ConfigError("malformed ceilings: $label.$sid.\"$sp\" must be an integer"))
            ci = Int(c)
            ci < 0 && throw(ConfigError("malformed ceilings: $label.$sid.\"$sp\" must be non-negative"))
            inner[sp] = ci
        end
        outer[sid] = inner
    end
    return outer
end

"""
    load_ceilings(root, policy)

Load and validate `.agentrulelint/ceilings.toml`.
Unknown top-level keys, unknown rule ids, or malformed counts are `ConfigError` (exit 2).
When the file is missing, returns empty ceilings (no enforcement slack).
"""
function load_ceilings(root::AbstractString, policy::PolicyBundle)
    path = _ceilings_path(root)
    !isfile(path) && return CeilingEntry(Dict(), Dict())
    raw = load_toml_file(path)
    known = _known_rule_ids(policy)
    viol = Dict{String, Dict{String, Int}}()
    exp = Dict{String, Dict{String, Int}}()
    for (k, v) in raw
        sk = String(k)
        if sk == CEILING_VIOLATIONS_PREFIX
            viol = _parse_ceiling_table(v, sk, "violations")
            continue
        elseif sk == CEILING_EXPECTS_PREFIX
            exp = _parse_ceiling_table(v, sk, "expects")
            continue
        end
        throw(ConfigError("malformed ceilings: unknown top-level key '$sk'"))
    end
    for rid in keys(viol)
        rid in known || throw(ConfigError("unknown rule id in ceilings violations: $rid"))
    end
    for rid in keys(exp)
        rid in known || throw(ConfigError("unknown rule id in ceilings expects: $rid"))
    end
    return CeilingEntry(viol, exp)
end

function count_violation_hits(diags::Vector{Violation})
    counts = Dict{String, Dict{String, Int}}()
    for d in diags
        is_violation_hit(d) || continue
        counts[d.rule_id] = get(counts, d.rule_id, Dict{String, Int}())
        counts[d.rule_id][d.path] = get(counts[d.rule_id], d.path, 0) + 1
    end
    return counts
end

function count_expect_lines(contexts::Vector{FileContext})
    counts = Dict{String, Dict{String, Int}}()
    for fc in contexts
        for ex in fc.expects
            ref = strip(ex.rule_ref)
            isempty(ref) && continue
            counts[ref] = get(counts, ref, Dict{String, Int}())
            counts[ref][fc.parsed.path] = get(counts[ref], fc.parsed.path, 0) + 1
        end
    end
    return counts
end

function _in_ratchet_scope(path::String, scope_paths::Union{Nothing, Set{String}})
    scope_paths === nothing && return true
    return path in scope_paths
end

function enforce_ceiling_ratchet(
        violation_counts::Dict{String, Dict{String, Int}},
        expect_counts::Dict{String, Dict{String, Int}},
        ceilings::CeilingEntry,
        policy::PolicyBundle;
        scope_paths = nothing,
    )
    out = Violation[]
    seen_viol = Set{Tuple{String, String}}()
    for (rid, paths) in violation_counts
        for (path, actual) in paths
            _in_ratchet_scope(path, scope_paths) || continue
            ceiling = get(get(ceilings.violations, rid, Dict{String, Int}()), path, 0)
            key = (rid, path)
            key in seen_viol && continue
            push!(seen_viol, key)
            if actual > ceiling
                msg = "violation count increased for $rid at $path: actual=$actual ceiling=$ceiling"
                push!(out, _ceiling_ratchet_diag(path, rid, msg, policy))
            end
        end
    end
    for (rid, paths) in ceilings.violations
        for (path, ceiling) in paths
            _in_ratchet_scope(path, scope_paths) || continue
            key = (rid, path)
            actual = get(get(violation_counts, rid, Dict{String, Int}()), path, 0)
            if actual > ceiling
                key in seen_viol && continue
                msg = "violation count increased for $rid at $path: actual=$actual ceiling=$ceiling"
                push!(out, _ceiling_ratchet_diag(path, rid, msg, policy))
            elseif actual < ceiling
                msg =
                    "violation count decreased for $rid at $path: actual=$actual ceiling=$ceiling (run agentrulelint ratchet --write)"
                push!(out, _ceiling_ratchet_diag(path, rid, msg, policy))
            end
        end
    end
    for (rid, paths) in ceilings.expects
        for (path, ceiling) in paths
            _in_ratchet_scope(path, scope_paths) || continue
            actual = get(get(expect_counts, rid, Dict{String, Int}()), path, 0)
            if actual > ceiling
                msg = "expect count increased for $rid at $path: actual=$actual ceiling=$ceiling"
                push!(out, _ceiling_ratchet_diag(path, rid, msg, policy))
            elseif actual < ceiling
                msg =
                    "expect count decreased for $rid at $path: actual=$actual ceiling=$ceiling (run agentrulelint ratchet --write)"
                push!(out, _ceiling_ratchet_diag(path, rid, msg, policy))
            end
        end
    end
    return out
end

function _ceiling_ratchet_diag(path::String, _rule_id::String, message::String, policy::PolicyBundle)
    spec = get(policy.rules, CEILING_RATCHET_RULE, nothing)
    intent = spec === nothing ? "Keep violation and expect ceilings monotonic (down only)." : spec.intent
    do_not = spec === nothing ? "Raise ceilings or leave stale slack after counts decrease." : spec.do_not
    return Violation(
        CEILING_RATCHET_RULE,
        :agentrulelint,
        :forbid,
        path,
        Span(1, 1, 1, 1),
        1,
        "",
        :none,
        false,
        message,
        intent,
        do_not,
    )
end
