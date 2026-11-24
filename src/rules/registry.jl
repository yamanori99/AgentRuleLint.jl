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
    if get(policy.rules, "silent-catch", nothing) === nothing
        register_builtin!(
            RuleSpec(
                "silent-catch",
                :agentrulelint,
                :deny,
                "Surface try/catch blocks that hide failures instead of rethrowing or throwing on unhandled paths.",
                "Use empty catch bodies, log-only handlers, or partial branches without rethrow to silence errors.",
                Dict{Symbol, String}(:warn_counts_as_handling => "false"),
            ),
        )
    end
    return nothing
end
