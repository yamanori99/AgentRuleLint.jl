# Immutable value types for JAILint (parse-don't-validate).

struct Span
    start_line::Int
    start_col::Int
    end_line::Int
    end_col::Int
end

Span() = Span(0, 0, 0, 0)

function Base.isless(a::Span, b::Span)
    return (a.start_line, a.start_col, a.end_line, a.end_col) <
        (b.start_line, b.start_col, b.end_line, b.end_col)
end

struct ConfigSource
    kind::Symbol
    path::String
    ref::String
    sha::String
end

ConfigSource() = ConfigSource(:builtin, "", "", "")

function config_source_dict(cs::ConfigSource)
    d = Dict{String, Any}("kind" => string(cs.kind))
    !isempty(cs.path) && (d["path"] = cs.path)
    !isempty(cs.ref) && (d["ref"] = cs.ref)
    !isempty(cs.sha) && (d["sha"] = cs.sha)
    return d
end

"""Single lint finding (`rule_id` is always a canonical slug)."""
struct Violation
    rule_id::String
    origin::Symbol
    level::Symbol
    path::String
    span::Span
    anchor_line::Int
    fingerprint::String
    expect_status::Symbol
    suppressed::Bool
    message::String
    intent::String
    do_not::String
end

struct CheckResult
    violations::Vector{Violation}
    complete::Bool
    exit_code::Int
    config_source::ConfigSource
    max_hits_per_rule::Int
    suppressed_count::Int
    violation_count::Int
end

struct ConfigError <: Exception
    msg::String
end

struct GitError <: Exception
    msg::String
end

struct ParseError <: Exception
    msg::String
end

struct InternalError <: Exception
    msg::String
end

struct RuleSpec
    id::String
    origin::Symbol
    level::Symbol
    intent::String
    do_not::String
    extra::Dict{Symbol, String}
end

struct ProjectRule
    id::String
    level::Symbol
    paths::Vector{String}
    forbid_literals::Vector{String}
    intent::String
    do_not::String
end

struct PolicyBundle
    jailint_version::VersionNumber
    default_format::Symbol
    max_hits_per_rule::Int
    presets::Vector{String}
    rules::Dict{String, RuleSpec}
    project_rules::Vector{ProjectRule}
    on_allow_rule::Symbol
    config_path::String
    config_source::ConfigSource
end

struct CeilingEntry
    violations::Dict{String, Dict{String, Int}}
    expects::Dict{String, Dict{String, Int}}
end

struct ExpectLine
    line::Int
    rule_ref::String
    reason::String
    raw::String
end

struct ParsedFile
    path::String
    source::String
    normalized::String
end

struct FileContext
    parsed::ParsedFile
    expects::Vector{ExpectLine}
    expect_errors::Vector{Violation}
end

struct RuleRunContext
    root::String
    policy::PolicyBundle
    ceilings::CeilingEntry
    files::Vector{FileContext}
    parser_rev::String
end

struct FoldedStringExpr
    value::String
    byte_start::Int
    byte_end::Int
end

const KEBAB_ID = r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$"

function validate_kebab_rule_id(id::AbstractString, label::AbstractString)
    s = String(id)
    occursin('/', s) && throw(ConfigError("$label: id must not contain '/' ($(s))"))
    match(KEBAB_ID, s) === nothing &&
        throw(ConfigError("$label: invalid kebab-case id ($(s))"))
    return s
end

is_fail_closed(err) =
    err isa ConfigError || err isa GitError || err isa ParseError

origin_label(o::Symbol) =
    o == :jailint ? "[JAILint]" : o == :preset ? "[Preset]" : "[Project]"

rule_display_id(r::RuleSpec) = r.id
project_rule_id(pr::ProjectRule) = "project/$(pr.id)"

function rule_ref_matches(rule_ref::String, diagnostic_rule_id::String)
    r = strip(rule_ref)
    d = strip(diagnostic_rule_id)
    r == d && return true
    d == "project/$r" && return true
    return false
end

function is_forbid_rule(policy::PolicyBundle, rule_ref::String)
    r = strip(rule_ref)
    for (_, spec) in policy.rules
        (spec.id == r || r == spec.id) && spec.level == :forbid && return true
    end
    for pr in policy.project_rules
        (r == pr.id || r == project_rule_id(pr)) && pr.level == :forbid && return true
    end
    return false
end
