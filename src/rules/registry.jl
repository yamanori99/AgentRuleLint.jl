const BUILTIN_RULES = Dict{String, RuleSpec}()

const EXPECT_AUDIT_EXPECT_ANCHOR = """
First non-blank code line after contiguous `# agentrulelint-expect:` lines that matches the target syntax kind for the referenced rule (e.g. `try`, `@eval`, `@test*`).
"""

const EXPECT_AUDIT_EXAMPLE = """
# agentrulelint-expect: expect-audit reason="documented suppression"
@eval :ok
"""

const EXPECT_AUDIT_SYNTAX = """
Syntax: `# agentrulelint-expect: <rule-id> reason="..."` (ASCII, standalone line only; non-empty reason).
"""

const EXPECT_AUDIT_SUPPRESSION = """
Suppresses only violations whose anchor_line matches that line.
Expects are forbidden above `catch`, inside `# runic: off` regions, inside multiline
call arguments, and with blank lines before the anchor. Forbidden placements do not
suppress violations. Multiline-call placement uses the same forbid level as other
expect-audit integrity findings.
"""

function expect_audit_explain_extra()
    return Dict{Symbol, String}(
        :expect_anchor => strip(EXPECT_AUDIT_EXPECT_ANCHOR),
        :syntax => strip(EXPECT_AUDIT_SYNTAX),
        :suppression => strip(EXPECT_AUDIT_SUPPRESSION),
        :example => strip(EXPECT_AUDIT_EXAMPLE),
    )
end

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
    id == "expect-audit" && return expect_audit_explain_extra()
    id == "unsafe-boundary" && return unsafe_boundary_explain_extra()
    id == "shell-safety/process-pattern" && return shell_safety_explain_extra()
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

const _DEFAULT_UNSAFE_BOUNDARY_SPEC = RuleSpec(
    "unsafe-boundary",
    :agentrulelint,
    :warn,
    "Keep runtime evaluation and FFI inside reviewed boundaries.",
    "Hide eval, ccall, or unsafe_* outside allow_modules / allow_globs.",
    Dict{Symbol, String}(),
)

const _DEFAULT_SHELL_SAFETY_SPEC = RuleSpec(
    "shell-safety/process-pattern",
    :preset,
    :deny,
    "Reject hazardous shell patterns in statically known Cmd literals.",
    "Split or dynamically assemble command strings to bypass constant folding.",
    Dict{Symbol, String}(),
)

function init_registry!(policy::PolicyBundle)
    empty!(BUILTIN_RULES)
    for (_, r) in policy.rules
        register_builtin!(r)
    end
    if policy.shell_safety.active
        spec = get(policy.rules, "shell-safety/process-pattern", _DEFAULT_SHELL_SAFETY_SPEC)
        register_builtin!(spec)
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
    if get(policy.rules, "scope-paths", nothing) === nothing
        register_builtin!(
            RuleSpec(
                "scope-paths",
                :agentrulelint,
                :forbid,
                "Reject diff changes outside a trusted path allowlist.",
                "Edit files outside --allow-paths scope passed from CI or a human wrapper.",
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
