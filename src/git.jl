# Config-isolated git on PATH (see #93). Minimum git 2.24.

const GIT_MIN_VERSION = VersionNumber("2.24")

const _TLS_GLOBAL_CONFIG = :agentrulelint_git_global_config
const _TLS_RUNTIME = :agentrulelint_git_runtime

function _task_tls()
    return task_local_storage()
end

function _git_global_config_path()
    tls = _task_tls()
    if haskey(tls, _TLS_GLOBAL_CONFIG)
        return tls[_TLS_GLOBAL_CONFIG]::String
    end
    Sys.iswindows() &&
        throw(InternalError("git isolation context missing (git_run_scope)"))
    # Test workers may call git helpers without `git_run_scope`; same empty global config.
    return "/dev/null"
end

function _git_isolated_env()
    return Dict{String, String}(
        "GIT_CONFIG_NOSYSTEM" => "1",
        "GIT_CONFIG_GLOBAL" => _git_global_config_path(),
        "GIT_TERMINAL_PROMPT" => "0",
        "GIT_OPTIONAL_LOCKS" => "0",
        "GIT_PAGER" => "cat",
        "LC_ALL" => "C",
    )
end

function git_runtime()
    tls = _task_tls()
    haskey(tls, _TLS_RUNTIME) || return (executable = "", version = "")
    return tls[_TLS_RUNTIME]::NamedTuple{(:executable, :version), Tuple{String, String}}
end

"""
    git_run_scope(f) -> f()

Set per-run git isolation context (`GIT_CONFIG_GLOBAL`, probe cache). On Windows,
uses a temporary directory removed after `f()` returns.
"""
function git_run_scope(f)
    return if Sys.iswindows()
        wdir = mktempdir()
        cfg = joinpath(wdir, "gitconfig")
        open(cfg, "w") do io
            # empty global config
        end
        tls = _task_tls()
        tls[_TLS_GLOBAL_CONFIG] = cfg
        try
            return f()
        finally
            delete!(tls, _TLS_RUNTIME)
            delete!(tls, _TLS_GLOBAL_CONFIG)
            rm(wdir, recursive = true, force = true)
        end
    else
        tls = _task_tls()
        tls[_TLS_GLOBAL_CONFIG] = "/dev/null"
        try
            return f()
        finally
            delete!(tls, _TLS_RUNTIME)
            delete!(tls, _TLS_GLOBAL_CONFIG)
        end
    end
end

function _parse_git_version_output(exe::AbstractString, out::AbstractString)
    s = strip(String(out))
    m = match(r"^git version (\d+\.\d+(?:\.\d+)?)", s)
    m === nothing &&
        throw(GitError("git at $exe produced unparseable --version output: $(repr(s))"))
    return VersionNumber(m.captures[1])
end

"""Probe PATH git via the isolated entry point; cache for this run."""
function ensure_git_runtime!(root::AbstractString)
    tls = _task_tls()
    if haskey(tls, _TLS_RUNTIME)
        rt = tls[_TLS_RUNTIME]
        !isempty(rt.version) && return rt
    end
    probe_root = (r = abspath(String(root)); isdir(r) ? r : pwd())
    exe = Sys.which("git")
    exe === nothing &&
        throw(GitError("git executable not found on PATH; AgentRuleLint requires git >= $GIT_MIN_VERSION"))
    exe = String(exe)
    tls[_TLS_RUNTIME] = (executable = exe, version = "")
    raw = strip(String(read_git_cmd(probe_root, "--version"; error_prefix = "git --version failed")))
    ver = _parse_git_version_output(exe, raw)
    ver < GIT_MIN_VERSION &&
        throw(
        GitError(
            "git at $exe reported version $ver; AgentRuleLint requires git >= $GIT_MIN_VERSION",
        ),
    )
    rt = (executable = exe, version = string(ver))
    tls[_TLS_RUNTIME] = rt
    return rt
end

function _git_executable_cmd(root::AbstractString)
    rt = git_runtime()
    if isempty(rt.executable)
        ensure_git_runtime!(root)
        rt = git_runtime()
    end
    return Cmd([rt.executable])
end

"""
    git_cmd(root, args...) -> Cmd

Build an isolated git command for `root` (`-C`, `safe.directory`, env isolation).
All AgentRuleLint and test git invocations must use this entry point.
"""
function git_cmd(root::AbstractString, args::AbstractString...)
    r = abspath(String(root))
    g = _git_executable_cmd(r)
    tail = Cmd(vcat(String["-C", r, "-c", "safe.directory=$(r)"], collect(String, args)))
    return addenv(`$g $tail`, _git_isolated_env()...)
end

"""Read stdout from an isolated git call; on failure raise `GitError` including stderr."""
function read_git_cmd(root::AbstractString, args::AbstractString...; error_prefix::AbstractString)
    return _read_git_cmd(git_cmd(root, args...); error_prefix = error_prefix)
end

"""Run an isolated git call (for tests and helpers)."""
function run_git_cmd(root::AbstractString, args::AbstractString...; cwd = nothing)
    cmd = git_cmd(root, args...)
    d = cwd === nothing ? root : String(cwd)
    return run(setenv(cmd; dir = d))
end

"""Read command stdout/stderr with deadlock-safe stderr drain (internal)."""
function _read_git_cmd(cmd::Cmd; error_prefix::AbstractString)
    out = Pipe()
    err = Pipe()
    proc = run(pipeline(cmd, stdout = out, stderr = err), wait = false)
    close(out.in)
    close(err.in)
    err_task = @async read(err)
    local stdout_data
    try
        stdout_data = read(out)
    catch
        fetch(err_task)
        rethrow()
    end
    stderr_data = fetch(err_task)
    wait(proc)
    if !success(proc)
        stderr_s = strip(String(stderr_data))
        detail = isempty(stderr_s) ? "exit $(proc.exitcode)" : "exit $(proc.exitcode): $stderr_s"
        throw(GitError("$error_prefix ($detail)"))
    end
    return stdout_data
end

function _git_toplevel(root::AbstractString)
    root = abspath(String(root))
    isdir(root) || throw(GitError("not a directory: $root"))
    return strip(String(read_git_cmd(root, "rev-parse", "--show-toplevel"; error_prefix = "not a git repository: $root")))
end

function _git_root(path::AbstractString)
    try
        return _git_toplevel(path)
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && rethrow()
        throw(GitError("not a git repository: $(abspath(String(path))): $(format_error(err))"))
    end
end

function _git_feature_not_repository(root::AbstractString, feature::AbstractString)
    error_prefix = "$feature requires a git repository at $(abspath(String(root)))"
    try
        _git_toplevel(root)
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && throw(GitError("$error_prefix ($(err.msg))"))
        throw(GitError("$error_prefix: $(format_error(err))"))
    end
    return nothing
end
