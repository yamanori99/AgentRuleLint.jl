# Immutable value types for JAILint (parse-don't-validate).

const RuleOrigin = Union{Val{:jailint}, Val{:preset}, Val{:project}}
const RuleLevel = Union{Val{:forbid}, Val{:deny}, Val{:warn}, Val{:allow}}
const ExpectStatus = Union{Val{:none}, Val{:fulfilled}, Val{:unfulfilled}}

rule_origin_symbol(::Val{:jailint}) = :jailint
rule_origin_symbol(::Val{:preset}) = :preset
rule_origin_symbol(::Val{:project}) = :project

rule_level_symbol(::Val{:forbid}) = :forbid
rule_level_symbol(::Val{:deny}) = :deny
rule_level_symbol(::Val{:warn}) = :warn
rule_level_symbol(::Val{:allow}) = :allow

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

struct Diagnostic
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
    diagnostics::Vector{Diagnostic}
    complete::Bool
    exit_code::Int
    config_source::Dict{String, Any}
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

struct LoadedRule
    code::String
    id::String
    origin::Symbol
    level::Symbol
    intent::String
    do_not::String
    extra::NamedTuple
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
    rules::Dict{String, LoadedRule}
    project_rules::Vector{ProjectRule}
    on_allow_rule::Symbol
    config_path::String
    source::Dict{String, Any}
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
    expect_errors::Vector{Diagnostic}
end

struct RuleRunContext
    root::String
    policy::PolicyBundle
    ceilings::CeilingEntry
    files::Vector{FileContext}
    parser_rev::String
end

RuleOriginType(o::Symbol) =
    o == :jailint ? Val(:jailint) :
    o == :preset ? Val(:preset) : Val(:project)

is_fail_closed(err) =
    err isa ConfigError || err isa GitError || err isa ParseError

origin_label(o::Symbol) =
    o == :jailint ? "[JAILint]" : o == :preset ? "[Preset]" : "[Project]"

rule_display_id(r::LoadedRule) = "$(r.code) $(r.id)"
project_rule_id(pr::ProjectRule) = "JP:$(pr.id)"
