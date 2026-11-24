const BUILTIN_RULES = Dict{String, LoadedRule}()

function register_builtin!(r::LoadedRule)
    return BUILTIN_RULES[r.id] = r
end

function init_registry!(policy::PolicyBundle)
    empty!(BUILTIN_RULES)
    for (_, r) in policy.rules
        register_builtin!(r)
    end
    return get(policy.rules, "expect-audit", nothing) === nothing &&
        register_builtin!(
        LoadedRule(
            "JA004",
            "expect-audit",
            :jailint,
            :forbid,
            "Keep suppression comments auditable.",
            "Hide violations with unapproved expects.",
            NamedTuple(),
        ),
    )
end

function builtin_rule_meta(code::String)
    if code == "JA004"
        return (
            intent = "Validate expect comments and suppression anchors.",
            do_not = "Use malformed or misplaced expects.",
        )
    end
    return (intent = "", do_not = "")
end
