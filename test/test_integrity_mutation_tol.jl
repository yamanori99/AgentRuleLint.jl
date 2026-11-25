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
    write(joinpath(dir, "test", "approx.jl"), "isapprox(1.0, 2.0; atol=1.0e-12)\n")
    run(setenv(Cmd(["git", "-C", dir, "add", "-A"]); dir = dir))
    run(
        setenv(
            Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base"]);
            dir = dir,
        ),
    )
    write(joinpath(dir, "test", "approx.jl"), "isapprox(1.0, 2.0; atol=1.0e-3)\n")
    run(setenv(Cmd(["git", "-C", dir, "add", "-A"]); dir = dir))
    run(
        setenv(
            Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "loose"]);
            dir = dir,
        ),
    )
    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
    ok = any(d -> occursin("tolerance loosened", d.message), res.violations)
    exit(ok ? 0 : 2)
finally
    rm(dir, recursive = true, force = true)
end
