# Pinned, config-isolated git via Git_jll (see #93).

using Git_jll

const _GIT_EMPTY_GLOBAL_CONFIG = Ref{Union{Nothing, String}}(nothing)

function _git_empty_global_config_path()
    existing = _GIT_EMPTY_GLOBAL_CONFIG[]
    existing !== nothing && return existing
    if Sys.iswindows()
        path, io = mktemp(prefix = "agentrulelint-gitconfig-")
        close(io)
        _GIT_EMPTY_GLOBAL_CONFIG[] = path
        return path
    end
    _GIT_EMPTY_GLOBAL_CONFIG[] = "/dev/null"
    return "/dev/null"
end

function _git_isolated_env()
    return Dict{String, String}(
        "GIT_CONFIG_NOSYSTEM" => "1",
        "GIT_CONFIG_GLOBAL" => _git_empty_global_config_path(),
        "GIT_TERMINAL_PROMPT" => "0",
        "GIT_OPTIONAL_LOCKS" => "0",
        "GIT_PAGER" => "cat",
        "LC_ALL" => "C",
    )
end

"""
    git_cmd(root, args...) -> Cmd

Build an isolated git command for `root` (`-C`, `safe.directory`, env isolation).
All AgentRuleLint and test git invocations must use this entry point.
"""
function git_cmd(root::AbstractString, args::AbstractString...)
    r = abspath(String(root))
    try
        g = Git_jll.git()
        tail = Cmd(vcat(String["-C", r, "-c", "safe.directory=$(r)"], collect(String, args)))
        return addenv(`$g $tail`, _git_isolated_env()...)
    catch err
        err isa InterruptException && rethrow()
        throw(GitError("bundled git (Git_jll) is unavailable on this platform: $(format_error(err))"))
    end
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
