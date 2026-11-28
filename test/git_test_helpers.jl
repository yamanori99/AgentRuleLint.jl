# Test-only git helpers; all test git invocations must go through here.

const _git = AgentRuleLint

"""
Git argv/env our entry point sets (no other repo code should bypass `git_cmd`):

- **Every call:** `-C <root>`, `-c safe.directory=<root>`, `-c core.attributesFile=<empty>`; env
  `GIT_CONFIG_NOSYSTEM=1`, `GIT_ATTR_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL` (empty per run),
  `GIT_TERMINAL_PROMPT=0`, `GIT_OPTIONAL_LOCKS=0`, `GIT_PAGER=cat`, `LC_ALL=C`.
- **`git diff` (name-status / numstat / unified):** `-c diff.renames=true`, `-M`,
  `--no-ext-diff`, `--no-textconv`, `--text` (name-status + unified), `--no-color` (unified).
- **Other subcommands** (`rev-parse`, `ls-files`, `ls-tree`, `show`, `config`, …): only
  the per-call flags above (no `diff.renames`, color, or attributes overrides).
"""

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

"""Successful `check(...; diff_base)` under `HOME`; throws `GitError` on fail-closed git paths."""
function git_isolation_check_result(dir::AbstractString, diff_base::AbstractString, home::AbstractString)
    dir = abspath(String(dir))
    base = String(diff_base)
    return withenv(
        "HOME" => home,
        "GIT_CONFIG_GLOBAL" => nothing,
        "GIT_CONFIG_NOSYSTEM" => nothing,
    ) do
        res = _git.check(dir; diff_base = base)
        return (
            kind = :result,
            violations = active_violation_paths(res),
            exit_code = res.exit_code,
            complete = res.complete,
        )
    end
end

"""Compare isolation probe outcomes: both must be complete results with matching signatures."""
function git_isolation_outcomes_equivalent(a, b)
    a.kind == :result && b.kind == :result || return false
    a.complete && b.complete || return false
    return a.violations == b.violations && a.exit_code == b.exit_code
end

"""Hostile default global attributes at HOME/.config/git/attributes (XDG unset)."""
function hostile_default_xdg_attributes_under_home!(home::AbstractString)
    home = abspath(String(home))
    d = joinpath(home, ".config", "git")
    mkpath(d)
    write(joinpath(d, "attributes"), "*.jl -diff\n")
    return nothing
end

"""Hostile default global attributes at XDG_CONFIG_HOME/git/attributes."""
function hostile_default_xdg_attributes_under_xdg!(xdg::AbstractString)
    xdg = abspath(String(xdg))
    d = joinpath(xdg, "git")
    mkpath(d)
    write(joinpath(d, "attributes"), "*.jl -diff\n")
    return nothing
end

"""
Hostile global config not overridden by our explicit git flags: `core.attributesfile`
with `*.jl -diff`. When `GIT_CONFIG_GLOBAL` isolation is missing, git still applies
global attributes to numstat probe (`--no-textconv` diff) and check fails closed on
binary probe for `.jl` paths; with isolation, global config is empty and both HOMEs match.
"""
function hostile_attributes_global_gitconfig!(hostile_home::AbstractString)
    hostile_home = abspath(String(hostile_home))
    attr = joinpath(hostile_home, "global-attrs")
    write(attr, "*.jl -diff\n")
    open(joinpath(hostile_home, ".gitconfig"), "w") do io
        println(io, "[core]")
        println(io, "\tattributesfile = $(attr)")
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
