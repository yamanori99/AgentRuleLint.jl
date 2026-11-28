using AgentRuleLint

include(joinpath(@__DIR__, "git_test_helpers.jl"))

const ROOT = normpath(joinpath(@__DIR__, ".."))
cfg = read(joinpath(ROOT, ".AgentRuleLint.jl.toml"), String)
AgentRuleLint.git_run_scope() do
    dir = abspath(mktempdir())
    try
        init_git_repo!(dir)
        write(joinpath(dir, ".AgentRuleLint.jl.toml"), cfg)
        mkpath(joinpath(dir, "test"))
        git_commit = () -> git_commit_all!(dir, "c")
        git_commit()
        write(joinpath(dir, "test", "new_skip.jl"), "@test_broken false\n")
        git_commit()
        res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
        ok = any(
            d -> d.rule_id == "test-integrity" && occursin("test_broken count increased", d.message),
            res.violations,
        )
        exit(ok ? 0 : 2)
    finally
        rm(dir, recursive = true, force = true)
    end
end