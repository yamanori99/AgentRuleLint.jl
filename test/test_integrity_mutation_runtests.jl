using AgentRuleLint

include(joinpath(@__DIR__, "git_test_helpers.jl"))

const ROOT = normpath(joinpath(@__DIR__, ".."))
cfg = read(joinpath(ROOT, ".AgentRuleLint.jl.toml"), String)
dir = abspath(mktempdir())
try
    init_git_repo!(dir)
    write(joinpath(dir, ".AgentRuleLint.jl.toml"), cfg)
    mkpath(joinpath(dir, "test"))
    write(joinpath(dir, "test", "runtests.jl"), "include(\"case.jl\")\n")
    write(joinpath(dir, "test", "case.jl"), "@test true\n")
    git_commit_all!(dir, "base")
    write(joinpath(dir, "test", "runtests.jl"), "# stripped\n")
    git_commit_all!(dir, "strip")
    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
    ok = any(d -> occursin("removed from test/runtests.jl", d.message), res.violations)
    exit(ok ? 0 : 2)
finally
    rm(dir, recursive = true, force = true)
end
