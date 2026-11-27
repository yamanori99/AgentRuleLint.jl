"""Rank of a finding level for exit-threshold comparison (`:warn` < `:deny` < `:forbid`)."""
function level_exit_rank(level::Symbol)
    level == :warn && return 1
    level == :deny && return 2
    level == :forbid && return 3
    return 0
end

"""Whether a diagnostic should set a non-zero exit code for `threshold` (`:forbid`, `:deny`, or `:warn`).

Findings at level `:forbid` always fail the check, regardless of threshold (integrity / expect-audit).
"""
function violation_counts_toward_exit(d::Violation, threshold::Symbol)
    is_violation_hit(d) || return false
    d.level == :forbid && return true
    return level_exit_rank(d.level) >= level_exit_rank(threshold)
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

"""Return `(threshold, threshold_source, baseline, baseline_source)`."""
function resolve_exit_severity(policy::PolicyBundle; exit_severity = nothing)
    baseline = policy.exit_severity
    baseline_src = policy.exit_severity_source
    if exit_severity === nothing
        return baseline, baseline_src, baseline, baseline_src
    end
    return _parse_exit_severity_cli(exit_severity), :cli, baseline, baseline_src
end
