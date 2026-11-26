"""Minimum violation levels that fail `check` for a given `exit_severity` threshold (JETLS-style)."""
const EXIT_SEVERITY_RANK = Dict(:warn => 1, :deny => 2, :forbid => 3)

const VIOLATION_EXIT_RANK = Dict(:warn => 1, :deny => 2, :forbid => 3)

"""Whether a diagnostic should set a non-zero exit code for `threshold` (`:forbid`, `:deny`, or `:warn`).

Findings at level `:forbid` always fail the check, regardless of threshold (integrity / expect-audit).
"""
function violation_counts_toward_exit(d::Violation, threshold::Symbol)
    is_violation_hit(d) || return false
    d.level == :forbid && return true
    r = get(VIOLATION_EXIT_RANK, d.level, 0)
    t = get(EXIT_SEVERITY_RANK, threshold, 1)
    return r >= t
end

function check_exit_code(diags, threshold::Symbol)
    return any(d -> violation_counts_toward_exit(d, threshold), diags) ? 1 : 0
end

function _parse_exit_severity(raw, label::AbstractString)
    s = raw isa AbstractString ? lowercase(strip(raw)) : raw isa Symbol ? lowercase(string(raw)) : ""
    isempty(s) && throw(ConfigError("missing exit_severity in $label"))
    sym = Symbol(s)
    sym in VALID_EXIT_SEVERITY ||
        throw(ConfigError("unknown exit_severity '$raw' in $label (expected forbid|deny|warn)"))
    return sym
end

function _parse_exit_severity_cli(raw)
    s = raw isa AbstractString ? lowercase(strip(raw)) : raw isa Symbol ? lowercase(string(raw)) : ""
    sym = Symbol(s)
    sym in VALID_EXIT_SEVERITY ||
        throw(ArgumentError("unknown --exit-severity value '$raw' (expected forbid|deny|warn)"))
    return sym
end

function resolve_exit_severity(policy::PolicyBundle; exit_severity = nothing)
    exit_severity === nothing && return policy.exit_severity
    return _parse_exit_severity_cli(exit_severity)
end