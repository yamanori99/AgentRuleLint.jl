# Test-only git helpers; all test git invocations must go through here.

const _git = AgentRuleLint

"""Initialize a temp repo with local identity (isolated git)."""
function init_git_repo!(dir::AbstractString)
    dir = abspath(String(dir))
    _git.run_git_cmd(dir, "init", "-q", "-b", "main"; cwd = dir)
    _git.run_git_cmd(dir, "config", "user.email", "agentrulelint@test"; cwd = dir)
    _git.run_git_cmd(dir, "config", "user.name", "agentrulelint"; cwd = dir)
    return nothing
end

function git_commit_all!(dir::AbstractString, msg::AbstractString)
    dir = abspath(String(dir))
    _git.run_git_cmd(dir, "add", "-A"; cwd = dir)
    _git.run_git_cmd(dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", String(msg); cwd = dir)
    return nothing
end

function git_read(repo::AbstractString, args::AbstractString...)
    return String(_git.read_git_cmd(abspath(String(repo)), args...; error_prefix = "test git failed"))
end

function git_repo_status_porcelain(
        repo::AbstractString;
        untracked_all::Bool = false,
        paths::Vector{String} = String[],
    )
    args = String["status", "--porcelain"]
    untracked_all && push!(args, "--untracked-files=all")
    !isempty(paths) && append!(args, vcat("--", paths))
    return git_read(repo, args...)
end

function minimal_project_cfg()
    ver = string(pkgversion(AgentRuleLint))
    return """
    agentrulelint_version = \"=$(ver)\"

    [[project_rules]]
    id = \"diff-literal\"
    level = \"deny\"
    paths = [\"**\"]
    forbid_literals = [\"FORBIDDEN_DIFF_TOKEN\"]
    intent = \"\"
    do_not = \"\"
    """
end

"""Sorted active violation `(rule_id, path)` pairs for git-isolation comparisons."""
function active_violation_paths(res::AgentRuleLint.CheckResult)
    active = AgentRuleLint.active_violations(res.violations)
    tup = Tuple{String, String}[(d.rule_id, d.path) for d in active]
    return sort(tup)
end

"""Observed `CheckResult` fields plus diff path events that drive diff filtering."""
function git_check_isolation_signature(dir::AbstractString, diff_base::AbstractString, home::AbstractString)
    dir = abspath(String(dir))
    base = String(diff_base)
    return withenv("HOME" => home) do
        res = _git.check(dir; diff_base = base)
        active = _git.active_violations(res.violations)
        viols = sort(Tuple{String, String, String}[(d.rule_id, d.path, d.message) for d in active])
        events = _git.git_diff_path_events(dir, base)
        evs = sort(Tuple{Char, String, String}[(e.status, e.path, e.old_path) for e in events])
        return (viols = viols, events = evs)
    end
end

function hostile_renames_global_gitconfig!(hostile_home::AbstractString)
    open(joinpath(hostile_home, ".gitconfig"), "w") do io
        println(io, "[diff]")
        println(io, "\trenames = false")
    end
    return nothing
end

function rename_diff_literal_isolation_fixture(dir::AbstractString)
    init_git_repo!(dir)
    write(joinpath(dir, ".AgentRuleLint.jl.toml"), minimal_project_cfg())
    write(joinpath(dir, "src.jl"), "v=1\nx=\"FORBIDDEN_DIFF_TOKEN\"\n")
    git_commit_all!(dir, "base")
    _git.run_git_cmd(dir, "mv", "src.jl", "dst.jl"; cwd = dir)
    git_commit_all!(dir, "rename only")
    return nothing
end

const GIT_ISOLATION_DIFF_BASE = "HEAD^1"
