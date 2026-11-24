const BUILTIN_RULES = Dict{String, RuleSpec}()

function register_builtin!(r::RuleSpec)
    return BUILTIN_RULES[r.id] = r
end

const _DEFAULT_UNSAFE_BOUNDARY_SPEC = RuleSpec(
    "unsafe-boundary",
    :agentrulelint,
    :warn,
    "Keep runtime evaluation and FFI inside reviewed boundaries.",
    "Hide eval, ccall, or unsafe_* outside allow_modules / allow_globs.",
    Dict{Symbol, String}(),
)

function init_registry!(policy::PolicyBundle)
    empty!(BUILTIN_RULES)
    for (_, r) in policy.rules
        register_builtin!(r)
    end
    if policy.unsafe_boundary.active && get(policy.rules, "unsafe-boundary", nothing) === nothing
        register_builtin!(_DEFAULT_UNSAFE_BOUNDARY_SPEC)
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
    return nothing
end
