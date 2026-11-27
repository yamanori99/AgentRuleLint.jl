# Test-only git helpers; all test git invocations must go through here.

const _git = AgentRuleLint

"""Initialize a temp repo with local identity (isolated bundled git)."""
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
