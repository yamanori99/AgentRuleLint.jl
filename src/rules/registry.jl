const BUILTIN_RULES = Dict{String, RuleSpec}()

const BUILTIN_DOC_DEFAULTS = Dict(
    "expect-audit" => (
        "Keep suppression comments auditable.",
        "Hide violations with unapproved expects.",
    ),
    "protected-paths" => (
        "Protect designated policy, lockfiles, and workflow paths from silent edits.",
        "Edit protected files, weaken compat, or rename paths to evade review.",
    ),
    "shell-safety/process-pattern" => (
        "Reject hazardous shell patterns in statically known Cmd literals.",
        "Split or dynamically assemble command strings to bypass constant folding.",
    ),
)

function fill_builtin_docs!(spec::RuleSpec)
    d = get(BUILTIN_DOC_DEFAULTS, spec.id, nothing)
    d === nothing && return spec
    intent = isempty(spec.intent) ? d[1] : spec.intent
    do_not = isempty(spec.do_not) ? d[2] : spec.do_not
    return RuleSpec(spec.id, spec.origin, spec.level, intent, do_not, spec.extra)
end

"""Attach built-in explain text that lives with the rule definition (config may override intent/do_not only)."""
function builtin_explain_extras(id::AbstractString)
    id == EXPECT_AUDIT_ID && return expect_audit_explain_extra()
    id == CEILING_RATCHET_RULE && return ceiling_ratchet_explain_extra()
    id == "unsafe-boundary" && return unsafe_boundary_explain_extra()
    id == SHELL_SAFETY_PRESET_ID && return shell_safety_explain_extra()
    id == SILENT_CATCH_ID && return silent_catch_explain_extra()
    id == MANIFEST_SYNC_RULE && return manifest_sync_explain_extra()
    id == SCOPE_PATHS_RULE && return scope_paths_explain_extra()
    id == PROTECTED_PATHS_RULE && return protected_paths_explain_extra()
    id == TEST_INTEGRITY_RULE && return test_integrity_explain_extra()
    return Dict{Symbol, String}()
end

function attach_rule_explain_docs(spec::RuleSpec)
    extras = builtin_explain_extras(spec.id)
    isempty(extras) && return spec
    extra = copy(spec.extra)
    for (k, v) in extras
        haskey(extra, k) || (extra[k] = v)
    end
    return RuleSpec(spec.id, spec.origin, spec.level, spec.intent, spec.do_not, extra)
end

function register_builtin!(r::RuleSpec)
    return BUILTIN_RULES[r.id] = attach_rule_explain_docs(fill_builtin_docs!(r))
end

function init_registry!(policy::PolicyBundle)
    empty!(BUILTIN_RULES)
    for (_, r) in policy.rules
        register_builtin!(r)
    end
    if policy.shell_safety.active
        spec = get(policy.rules, SHELL_SAFETY_PRESET_ID, rule_def_to_spec(SHELL_SAFETY_RULE_DEF))
        register_builtin!(spec)
    end
    if policy.unsafe_boundary.active && get(policy.rules, "unsafe-boundary", nothing) === nothing
        register_builtin!(rule_def_to_spec(UNSAFE_BOUNDARY_RULE_DEF))
    end
    if get(policy.rules, EXPECT_AUDIT_ID, nothing) === nothing
        register_builtin!(rule_def_to_spec(EXPECT_AUDIT_RULE_DEF))
    end
    if get(policy.rules, SILENT_CATCH_ID, nothing) === nothing
        register_builtin!(rule_def_to_spec(SILENT_CATCH_RULE_DEF))
    end
    if get(policy.rules, MANIFEST_SYNC_RULE, nothing) === nothing
        register_builtin!(rule_def_to_spec(MANIFEST_SYNC_RULE_DEF))
    end
    if get(policy.rules, SCOPE_PATHS_RULE, nothing) === nothing
        register_builtin!(rule_def_to_spec(SCOPE_PATHS_RULE_DEF))
    end
    if get(policy.rules, PROTECTED_PATHS_RULE, nothing) === nothing
        register_builtin!(rule_def_to_spec(PROTECTED_PATHS_RULE_DEF))
    end
    return nothing
end
