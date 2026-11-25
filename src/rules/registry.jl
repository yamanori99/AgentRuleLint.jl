const BUILTIN_RULES = Dict{String, RuleSpec}()

# Same three ids as `main`'s `BUILTIN_DOC_DEFAULTS`. Text comes from `RuleDef`
# (no duplicated table). Widening this set is an intentional output change and
# belongs in a separate PR that updates the no_config / minimal_config goldens.
const BUILTIN_DOC_FILL_IDS = Set(
    [
        "expect-audit",
        "protected-paths",
        SHELL_SAFETY_PRESET_ID,
    ]
)

"""Fill empty intent/do_not from `RuleDef` for the historical three-id set only.

Config values win when present. Other rule ids keep empty intent/do_not when the
config omits them (behavior-neutral vs `main`).
"""
function fill_builtin_docs!(spec::RuleSpec)
    spec.id in BUILTIN_DOC_FILL_IDS || return spec
    def = get(RULE_DEFS_BY_ID, spec.id, nothing)
    def === nothing && return spec
    intent = isempty(spec.intent) ? def.intent : spec.intent
    do_not = isempty(spec.do_not) ? def.do_not : spec.do_not
    return RuleSpec(spec.id, spec.origin, spec.level, intent, do_not, spec.extra)
end

"""Attach built-in explain text that lives with the rule definition (config may override intent/do_not only)."""
function builtin_explain_extras(id::AbstractString)
    id == ANALYSIS_INCOMPLETE_RULE && return analysis_incomplete_explain_extra()
    id == EXPECT_AUDIT_ID && return expect_audit_explain_extra()
    id == "unsafe-boundary" && return unsafe_boundary_explain_extra()
    id == SHELL_SAFETY_PRESET_ID && return shell_safety_explain_extra()
    id == SILENT_CATCH_ID && return silent_catch_explain_extra()
    id == MANIFEST_SYNC_RULE && return manifest_sync_explain_extra()
    id == SCOPE_PATHS_RULE && return scope_paths_explain_extra()
    id == PROTECTED_PATHS_RULE && return protected_paths_explain_extra()
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
    if get(policy.rules, ANALYSIS_INCOMPLETE_RULE, nothing) === nothing
        register_builtin!(rule_def_to_spec(ANALYSIS_INCOMPLETE_RULE_DEF))
    end
    return nothing
end
