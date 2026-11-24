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
    if get(policy.rules, "protected-paths", nothing) === nothing
        register_builtin!(
            RuleSpec(
                "protected-paths",
                :agentrulelint,
                :forbid,
                "Protect designated policy, lockfiles, and workflow paths from silent edits.",
                "Edit protected files, weaken compat, or rename paths to evade review.",
                Dict{Symbol, String}(),
            ),
        )
    end
    return nothing
end
