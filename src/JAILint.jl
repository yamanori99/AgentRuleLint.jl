module JAILint

using JuliaSyntax
using PrecompileTools
using StyledStrings
using TOML
using SHA: sha1

export check, CheckResult, Span, Diagnostic, run_check, resolve_policy, main
export normalize_source, parse_source, folded_string_literals
export format_json, format_human, format_agent, explain_rule

const JAILINT_VERSION = pkgversion(@__MODULE__)

include("types.jl")
include("fingerprints.jl")
include("syntax/SyntaxAdapter.jl")
include("config.jl")
include("diff.jl")
include("expect.jl")
include("rules/registry.jl")
include("rules/project_rules.jl")
include("runner.jl")
include("format/json.jl")
include("format/human.jl")
include("format/agent.jl")
include("format/report.jl")

function check(root::AbstractString; kwargs...)
    try
        return run_check(root; kwargs...)
    catch err
        is_fail_closed(err) && rethrow()
        throw(InternalError(string(err)))
    end
end

function _parse_cli_args(args::Vector{String})
    cmd = isempty(args) ? "check" : args[1]
    rest = length(args) > 1 ? args[2:end] : String[]
    opts = Dict{Symbol, Any}(
        :format => :human,
        :config_path => nothing,
        :config_from => nothing,
        :diff_base => nothing,
        :output => nothing,
        :paths => String[],
        :write_ratchet => false,
    )
    i = 1
    positional = String[]
    while i <= length(rest)
        a = rest[i]
        if a == "--format" && i + 1 <= length(rest)
            opts[:format] = Symbol(rest[i + 1])
            i += 2
            continue
        elseif startswith(a, "--format=")
            opts[:format] = Symbol(a[(length("--format=") + 1):end])
        elseif a == "--config" && i + 1 <= length(rest)
            opts[:config_path] = rest[i + 1]
            i += 2
            continue
        elseif a == "--config-from" && i + 1 <= length(rest)
            opts[:config_from] = rest[i + 1]
            i += 2
            continue
        elseif a == "--diff" && i + 1 <= length(rest)
            opts[:diff_base] = rest[i + 1]
            i += 2
            continue
        elseif a == "--output" && i + 1 <= length(rest)
            opts[:output] = rest[i + 1]
            i += 2
            continue
        elseif a == "--write"
            opts[:write_ratchet] = true
        elseif startswith(a, "-")
            throw(ArgumentError("unknown option: $a"))
        else
            push!(positional, a)
        end
        i += 1
    end
    return cmd, positional, opts
end

function _exit_code(err)
    err isa InternalError && return 3
    is_fail_closed(err) && return 2
    err isa ArgumentError && return 2
    return 2
end

function _emit(result::CheckResult, opts)
    fmt = opts[:format]
    text = fmt == :json ? format_json(result) :
        fmt == :agent ? format_agent(result) :
        format_human(result)
    out = opts[:output]
    return if out === nothing
        print(text)
    else
        write(out, text)
    end
end

function _cli_check(positional::Vector{String}, opts)
    root = pwd()
    paths = isempty(positional) ? String[] : positional
    result = run_check(
        root;
        paths = paths,
        config_path = opts[:config_path],
        config_from = opts[:config_from],
        diff_base = opts[:diff_base],
    )
    opts[:write_ratchet] && ratchet_write!(root, result)
    _emit(result, opts)
    return result.exit_code
end

function _cli_explain(positional::Vector{String}, ::Dict)
    isempty(positional) && throw(ArgumentError("explain requires <code|id>"))
    println(explain_rule(positional[1]))
    return 0
end

function _cli_report(positional::Vector{String}, ::Dict)
    isempty(positional) && throw(ArgumentError("report requires <fingerprint>"))
    # offline: fingerprint lookup would need diagnostic store; emit minimal header
    fp = positional[1]
    dummy = Diagnostic(
        "JA004",
        :jailint,
        :forbid,
        "",
        Span(),
        0,
        fp,
        :none,
        false,
        "",
        "",
        "",
    )
    print(format_report(fp, dummy, "# placeholder\n"))
    return 0
end

function _cli_ratchet(positional::Vector{String}, opts)
    root = pwd()
    paths = positional
    result = run_check(
        root;
        paths = paths,
        config_path = opts[:config_path],
        config_from = opts[:config_from],
        diff_base = opts[:diff_base],
    )
    ratchet_write!(root, result)
    println("Wrote $(abspath(joinpath(root, ".jailint/ceilings.toml")))")
    return result.exit_code
end

function _main_impl(args = ARGS)
    cmd, positional, opts = _parse_cli_args(collect(args))
    return if cmd == "check"
        _cli_check(positional, opts)
    elseif cmd == "explain"
        _cli_explain(positional, opts)
    elseif cmd == "ratchet"
        opts[:write_ratchet] = true
        _cli_ratchet(positional, opts)
    elseif cmd == "report"
        _cli_report(positional, opts)
    elseif cmd == "help" || cmd == "-h" || cmd == "--help"
        println("Usage: jailint check [paths...] | explain <id> | ratchet --write | report <fingerprint>")
        0
    else
        throw(ArgumentError("unknown command: $cmd"))
    end
end

function main(args = ARGS)
    return try
        exit(_main_impl(args))
    catch err
        if err isa InternalError
            println(stderr, "JAILint internal error: ", err.msg)
            exit(3)
        elseif is_fail_closed(err)
            println(stderr, "JAILint fail-closed: ", sprint(showerror, err))
            exit(2)
        elseif err isa ArgumentError
            println(stderr, "JAILint: ", err.msg)
            exit(2)
        else
            println(stderr, "JAILint bug: ", sprint(showerror, err))
            exit(3)
        end
    end
end

@setup_workload begin
    try
        _ = self_check_parser("1 + 1\n")
    catch
    end
end

end # module JAILint
