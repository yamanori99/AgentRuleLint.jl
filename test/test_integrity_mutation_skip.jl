using AgentRuleLint

const ROOT = normpath(joinpath(@__DIR__, ".."))
cfg = read(joinpath(ROOT, ".AgentRuleLintConfig.toml"), String)
dir = abspath(mktempdir())
try
    run(`git -C $dir init -q -b main`)
    run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "m@t"]); dir = dir))
    run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "m"]); dir = dir))
    write(joinpath(dir, ".AgentRuleLintConfig.toml"), cfg)
    mkpath(joinpath(dir, "test"))
    git_commit = function ()
        run(setenv(Cmd(["git", "-C", dir, "add", "-A"]); dir = dir))
        return run(
            setenv(
                Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "c"]);
                dir = dir,
            ),
        )
    end
    git_commit()
    write(joinpath(dir, "test", "new_skip.jl"), "@test_broken false\n")
    git_commit()
    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
    ok = any(
        d -> d.rule_id == "test-integrity" && occursin("test_broken count increased", d.message),
        res.violations,
    )
    exit(ok ? 0 : 1)
finally
    rm(dir, recursive = true, force = true)
end
