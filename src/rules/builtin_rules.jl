# Explicit sorted registration of one-file-per-rule modules.
# Sort key: RuleDef.id (ASCII). Do not use glob-based includes.

include("analysis_incomplete.jl")
include("ceiling_ratchet.jl")
include("expect_audit.jl")
include("manifest_sync.jl")
include("protected_paths.jl")
include("scope_paths.jl")
include("shell_safety.jl")
include("silent_catch.jl")
include("test_integrity.jl")
include("unsafe_boundary.jl")
include("unsafe_boundary_strict.jl")

"""Canonical built-in / preset rule definitions, sorted by `id`."""
const RULE_DEFS = (
    ANALYSIS_INCOMPLETE_RULE_DEF,
    CEILING_RATCHET_RULE_DEF,
    EXPECT_AUDIT_RULE_DEF,
    MANIFEST_SYNC_RULE_DEF,
    PROTECTED_PATHS_RULE_DEF,
    SCOPE_PATHS_RULE_DEF,
    SHELL_SAFETY_RULE_DEF,
    SILENT_CATCH_RULE_DEF,
    TEST_INTEGRITY_RULE_DEF,
    UNSAFE_BOUNDARY_RULE_DEF,
    UNSAFE_BOUNDARY_STRICT_RULE_DEF,
)

function _assert_rule_defs_sorted!()
    ids = [d.id for d in RULE_DEFS]
    sorted = sort(ids)
    ids == sorted ||
        throw(InternalError("RULE_DEFS must be sorted by id; got $(ids), want $(sorted)"))
    return nothing
end

_assert_rule_defs_sorted!()

const RULE_DEFS_BY_ID = Dict{String, RuleDef}(d.id => d for d in RULE_DEFS)

function _run_unsafe_boundary_rule(fc::FileContext, policy::PolicyBundle)
    diags = Violation[]
    cfg = policy.unsafe_boundary
    cfg.active || return diags
    path_matches_glob(fc.parsed.path, cfg.allow_globs) && return diags
    eff = _effective_rule_level(policy, cfg.level)
    eff == :allow && return diags
    append!(diags, diagnose_unsafe_boundary(fc, policy, eff))
    return diags
end

function _run_unsafe_boundary_strict_rule(fc::FileContext, policy::PolicyBundle)
    diags = Violation[]
    cfg = policy.unsafe_boundary_strict
    cfg.active || return diags
    ub = _unsafe_boundary_allow_cfg(policy)
    path_matches_glob(fc.parsed.path, ub.allow_globs) && return diags
    eff = _effective_rule_level(policy, cfg.level)
    eff == :allow && return diags
    append!(diags, diagnose_unsafe_boundary_strict(fc, policy, cfg, eff))
    return diags
end

function _run_shell_safety_rule(fc::FileContext, policy::PolicyBundle)
    diags = Violation[]
    cfg = policy.shell_safety
    cfg.active || return diags
    eff = _effective_rule_level(policy, cfg.level)
    eff == :allow && return diags
    append!(diags, diagnose_shell_safety(fc, policy, eff))
    return diags
end

function run_builtin_rules(fc::FileContext, policy::PolicyBundle)
    diags = Violation[]
    julia_source_path(fc.parsed.path) || return diags
    append!(diags, _run_unsafe_boundary_rule(fc, policy))
    append!(diags, _run_unsafe_boundary_strict_rule(fc, policy))
    append!(diags, _run_shell_safety_rule(fc, policy))
    return diags
end
