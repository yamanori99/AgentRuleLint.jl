using AgentRuleLint

const ROOT = normpath(joinpath(@__DIR__, ".."))
cfg = read(joinpath(ROOT, ".AgentRuleLint.jl.toml"), String)
dir = abspath(mktempdir())
try
    run(`git -C $dir init -q -b main`)
    run(setenv(Cmd(["git", "-C", dir, "config", "user.email", "m@t"]); dir = dir))
    run(setenv(Cmd(["git", "-C", dir, "config", "user.name", "m"]); dir = dir))
    write(joinpath(dir, ".AgentRuleLint.jl.toml"), cfg)
    mkpath(joinpath(dir, "test"))
    write(joinpath(dir, "test", "runtests.jl"), "include(\"case.jl\")\n")
    write(joinpath(dir, "test", "case.jl"), "@test true\n")
    run(setenv(Cmd(["git", "-C", dir, "add", "-A"]); dir = dir))
    run(
        setenv(
            Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base"]);
            dir = dir,
        ),
    )
    write(joinpath(dir, "test", "runtests.jl"), "# stripped\n")
    run(setenv(Cmd(["git", "-C", dir, "add", "-A"]); dir = dir))
    run(
        setenv(
            Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "strip"]);
            dir = dir,
        ),
    )
    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
    ok = any(d -> occursin("removed from test/runtests.jl", d.message), res.violations)
    exit(ok ? 0 : 2)
finally
    rm(dir, recursive = true, force = true)
end
