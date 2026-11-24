const BUILTIN_RULES = Dict{String, RuleSpec}()

const EXPECT_AUDIT_EXPECT_ANCHOR = """
First non-blank code line after contiguous `# agentrulelint-expect:` lines that matches the target syntax kind for the referenced rule (e.g. `try`, `@eval`, `@test*`).
"""

const EXPECT_AUDIT_EXAMPLE = """
# agentrulelint-expect: expect-audit reason="documented suppression"
@eval :ok
"""

function expect_audit_explain_extra()
    return Dict{Symbol, String}(
        :expect_anchor => strip(EXPECT_AUDIT_EXPECT_ANCHOR),
        :example => strip(EXPECT_AUDIT_EXAMPLE),
    )
end

"""Attach built-in explain text that lives with the rule definition (config may override intent/do_not only)."""
function attach_rule_explain_docs(spec::RuleSpec)
    spec.id == "expect-audit" || return spec
    extra = copy(spec.extra)
    for (k, v) in expect_audit_explain_extra()
        haskey(extra, k) || (extra[k] = v)
    end
    return RuleSpec(spec.id, spec.origin, spec.level, spec.intent, spec.do_not, extra)
end

function register_builtin!(r::RuleSpec)
    return BUILTIN_RULES[r.id] = attach_rule_explain_docs(r)
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
    return nothing
end
