using AgentRuleLint

include(joinpath(@__DIR__, "git_test_helpers.jl"))

const run_git_cmd = AgentRuleLint.run_git_cmd
const ROOT = normpath(joinpath(@__DIR__, ".."))
cfg = read(joinpath(ROOT, ".AgentRuleLint.jl.toml"), String)
AgentRuleLint.git_run_scope() do
    dir = abspath(mktempdir())
    try
        init_git_repo!(dir)
        write(joinpath(dir, ".AgentRuleLint.jl.toml"), cfg)
        mkpath(joinpath(dir, "test"))
        write(joinpath(dir, "test", "approx.jl"), "isapprox(1.0, 2.0; atol=1.0e-12)\n")
        run_git_cmd(dir, "add", "-A"; cwd = dir)
        git_commit_all!(dir, "base")
        write(joinpath(dir, "test", "approx.jl"), "isapprox(1.0, 2.0; atol=1.0e-3)\n")
        run_git_cmd(dir, "add", "-A"; cwd = dir)
        git_commit_all!(dir, "loose")
        res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
        ok = any(d -> occursin("tolerance loosened", d.message), res.violations)
        exit(ok ? 0 : 2)
    finally
        rm(dir, recursive = true, force = true)
    end
end