const BUILTIN_RULES = Dict{String, RuleSpec}()

function register_builtin!(r::RuleSpec)
    return BUILTIN_RULES[r.id] = r
end

function init_registry!(policy::PolicyBundle)
    empty!(BUILTIN_RULES)
    for (_, r) in policy.rules
        register_builtin!(r)
    end
    if get(policy.rules, "expect-audit", nothing) === nothing
        register_builtin!(
            RuleSpec(
                "expect-audit",
                :agentrulelint,
                :forbid,
                "Keep suppression comments auditable.",
                "Hide violations with unapproved expects.",
                Dict{Symbol, String}(),
            ),
        )
    end
    if get(policy.rules, "manifest-sync", nothing) === nothing
        register_builtin!(
            RuleSpec(
                "manifest-sync",
                :agentrulelint,
                :deny,
                "Tracked manifests must match Project.toml.",
                "Drift project resolve sections away from the manifest.",
                Dict{Symbol, String}(:group => "integrity"),
            ),
        )
    end
    return nothing
end
