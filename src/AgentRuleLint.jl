module AgentRuleLint

using JuliaSyntax
using PrecompileTools
using StyledStrings
using TOML
using SHA: sha1

export CheckResult, RuleSpec, Span, Violation, check
export ConfigError, GitError, InternalError, ParseError

const AGENTRULELINT_VERSION = pkgversion(@__MODULE__)

include("types.jl")
include("fingerprints.jl")
include("path_glob.jl")
include("syntax/SyntaxAdapter.jl")
include("config.jl")
include("diff.jl")
include("ratchet.jl")
include("expect.jl")
include("rules/registry.jl")
include("rules/project_rules.jl")
include("rules/builtin_rules.jl")
include("rules/unsafe_boundary.jl")
include("rules/protected_paths.jl")
include("runner.jl")
include("format/json.jl")
include("format/width.jl")
include("format/human.jl")
include("format/agent.jl")
include("format/report.jl")

function check(root::AbstractString; kwargs...)
    try
        return run_check(root; kwargs...)
    catch err
        if err isa InterruptException
            rethrow()
        end
        is_fail_closed(err) && rethrow()
        throw(InternalError(string(err)))
    end
end

function _parse_cli_format(raw::AbstractString)
    sym = Symbol(lowercase(strip(raw)))
    sym in VALID_OUTPUT_FORMATS ||
        throw(ArgumentError("unknown --format value '$raw' (expected human|json|agent)"))
    return sym
end

function _parse_cli_args(cmd::String, rest::Vector{String})
    opts = Dict{Symbol, Any}(
        :format => nothing,
        :config_path => nothing,
        :config_from => nothing,
        :diff_base => nothing,
        :diff_mode => false,
        :output => nothing,
        :paths => String[],
        :write_ratchet => false,
    )
    i = 1
    positional = String[]
    while i <= length(rest)
        a = rest[i]
        if a == "--format" && i + 1 <= length(rest)
            opts[:format] = _parse_cli_format(rest[i + 1])
            i += 2
            continue
        elseif startswith(a, "--format=")
            opts[:format] = _parse_cli_format(a[(length("--format=") + 1):end])
        elseif a == "--config" && i + 1 <= length(rest)
            opts[:config_path] = rest[i + 1]
            i += 2
            continue
        elseif a == "--config-from" && i + 1 <= length(rest)
            opts[:config_from] = rest[i + 1]
            i += 2
            continue
        elseif a == "--diff"
            if i + 1 <= length(rest) && !startswith(rest[i + 1], "-")
                opts[:diff_base] = rest[i + 1]
                i += 2
            else
                opts[:diff_mode] = true
                i += 1
            end
            continue
        elseif a == "--output" && i + 1 <= length(rest)
            opts[:output] = rest[i + 1]
            i += 2
            continue
        elseif a == "--write"
            cmd == "ratchet" || throw(
                ArgumentError("unknown option for $cmd: --write (use agentrulelint ratchet --write)"),
            )
            opts[:write_ratchet] = true
        elseif startswith(a, "-")
            throw(ArgumentError("unknown option: $a"))
        else
            push!(positional, a)
        end
        i += 1
    end
    return positional, opts
end

function _emit_fail_closed(err, io = stderr)
    if err isa InternalError
        println(io, "AgentRuleLint internal error: ", err.msg)
        return 3
    elseif is_fail_closed(err)
        println(io, "AgentRuleLint fail-closed: ", sprint(showerror, err))
        return 2
    elseif err isa ArgumentError
        println(io, "AgentRuleLint: ", err.msg)
        return 2
    else
        println(io, "AgentRuleLint bug: ", sprint(showerror, err))
        return 3
    end
end

function _resolve_emit_format(result::CheckResult, opts)
    fmt = opts[:format]
    if fmt === nothing
        return result.default_format
    end
    fmt in VALID_OUTPUT_FORMATS ||
        throw(ArgumentError("unknown --format value '$fmt' (expected human|json|agent)"))
    return fmt
end

function _emit(result::CheckResult, fmt::Symbol, opts)
    fmt in VALID_OUTPUT_FORMATS ||
        throw(ArgumentError("unknown --format value '$fmt' (expected human|json|agent)"))
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

function _resolve_diff_kw(opts)
    if opts[:diff_base] !== nothing
        return resolve_diff_base_arg(opts[:diff_base])
    elseif opts[:diff_mode]
        return DEFAULT_DIFF_BASE
    end
    return nothing
end

function _cli_check(positional::Vector{String}, opts)
    root = pwd()
    paths = isempty(positional) ? String[] : positional
    result = check(
        root;
        paths = paths,
        config_path = opts[:config_path],
        config_from = opts[:config_from],
        diff_base = _resolve_diff_kw(opts),
    )
    fmt = _resolve_emit_format(result, opts)
    _emit(result, fmt, opts)
    return result.exit_code
end

function _cli_explain(positional::Vector{String}, ::Dict)
    isempty(positional) && throw(ArgumentError("explain requires <code|id>"))
    println(explain_rule(positional[1]))
    return 0
end

function _cli_report(positional::Vector{String}, ::Dict)
    isempty(positional) && throw(ArgumentError("report requires <fingerprint>"))
    fp = positional[1]
    root = pwd()
    result = check(root)
    matches = filter(d -> d.fingerprint == fp, result.violations)
    isempty(matches) && throw(ArgumentError("fingerprint not found: $fp"))
    d = first(matches)
    ap = joinpath(root, d.path)
    src = isfile(ap) ? normalize_source(read(ap, String)) : ""
    print(format_report(fp, d, src))
    return 0
end

function _ratchet_scope_paths(root::AbstractString, diff_base, paths::Vector{String}, policy::PolicyBundle)
    if diff_base !== nothing
        project_regexes = project_rule_path_regexes(policy)
        return Set(
            discover_files(root; paths = String[], diff_base = diff_base, project_regexes = project_regexes),
        )
    elseif !isempty(paths)
        project_regexes = project_rule_path_regexes(policy)
        return Set(discover_files(root; paths = paths, diff_base = nothing, project_regexes = project_regexes))
    end
    return Set{String}()
end

function _cli_ratchet(positional::Vector{String}, opts)
    root = pwd()
    paths = positional
    diff_base = _resolve_diff_kw(opts)
    result, contexts = run_check_pipeline(
        root;
        paths = paths,
        config_path = opts[:config_path],
        config_from = opts[:config_from],
        diff_base = diff_base,
    )
    policy = resolve_policy(
        root;
        config_path = opts[:config_path],
        config_from = opts[:config_from],
    )
    scope_paths = _ratchet_scope_paths(root, diff_base, paths, policy)
    merge_scope = diff_base !== nothing || !isempty(paths)
    ratchet_write!(
        root,
        result,
        contexts;
        merge_scope = merge_scope,
        scope_paths = scope_paths,
        policy = policy,
    )
    println("Wrote $(abspath(joinpath(root, ".agentrulelint/ceilings.toml")))")
    return result.exit_code
end

function _print_cli_help(cmd::String)
    if cmd == "check" || cmd == "help" || cmd == "-h" || cmd == "--help" || cmd == ""
        println(
            """
            Usage: agentrulelint check [paths...] [options]
                   agentrulelint explain <rule-id>
                   agentrulelint ratchet --write [paths...] [options]
                   agentrulelint report <fingerprint>

            Commands:
              check    Lint Julia sources (default). Reads ceilings; does not write them.
              explain  Print rule intent and anchor semantics for <rule-id>.
              ratchet  Update .agentrulelint/ceilings.toml from current violation counts (--write required).
              report   Emit anonymized JSON for a diagnostic fingerprint.

            Options (check and ratchet --write):
              --format human|json|agent   Output format (default: config default_format; invalid values exit 2)
              --config <path>             Alternate config file path
              --config-from <git-ref>     Load .AgentRuleLintConfig.toml from a git ref
              --diff [<base-ref>]         Limit to changed files/lines vs base (default: HEAD^1)
              --output <path>             Write formatted output to <path>

            Config is fail-closed: unknown keys, rule levels, preset names, or default_format values error.
            """,
        )
    elseif cmd == "ratchet"
        println(
            """
            Usage: agentrulelint ratchet --write [paths...] [options]

            Writes .agentrulelint/ceilings.toml from current violation counts. --write is required.
            A plain check run never updates ceilings.

            Options: same as agentrulelint check (see agentrulelint --help).
            """,
        )
    else
        println("Run agentrulelint --help for usage.")
    end
    return nothing
end

function cli_main(args::AbstractVector{<:AbstractString})::Int
    argvec = String[string(a) for a in args]
    try
        cmd = isempty(argvec) ? "check" : argvec[1]
        if cmd == "help" || cmd == "-h" || cmd == "--help"
            _print_cli_help("help")
            return 0
        end
        rest = length(argvec) > 1 ? argvec[2:end] : String[]
        known_cmds = ("check", "explain", "ratchet", "report")
        cmd in known_cmds || throw(ArgumentError("unknown command: $cmd"))
        if "--help" in rest || "-h" in rest
            _print_cli_help(cmd)
            return 0
        end
        positional, opts = _parse_cli_args(cmd, rest)
        return if cmd == "check"
            _cli_check(positional, opts)
        elseif cmd == "explain"
            _cli_explain(positional, opts)
        elseif cmd == "ratchet"
            opts[:write_ratchet] ||
                throw(ArgumentError("ratchet requires --write (updates .agentrulelint/ceilings.toml)"))
            _cli_ratchet(positional, opts)
        elseif cmd == "report"
            _cli_report(positional, opts)
        else
            throw(ArgumentError("unknown command: $cmd"))
        end
    catch err
        if err isa InterruptException
            rethrow()
        end
        return _emit_fail_closed(err)
    end
end

function (@main)(args::Vector{String})::Cint
    return Cint(cli_main(args))
end

@setup_workload begin
    try
        _ = self_check_parser("1 + 1\n")
    catch err
        err isa InterruptException && rethrow()
    end
end

end # module AgentRuleLint
