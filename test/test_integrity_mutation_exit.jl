using AgentRuleLint

const ROOT = normpath(joinpath(@__DIR__, ".."))
cfg = read(joinpath(ROOT, ".AgentRuleLintConfig.toml"), String)
dir = abspath(mktempdir())
try
    write(joinpath(dir, ".AgentRuleLintConfig.toml"), cfg)
    mkpath(joinpath(dir, "test"))
    write(joinpath(dir, "test", "runtests.jl"), "include(\"early.jl\")\n")
    write(joinpath(dir, "test", "early.jl"), "exit(0)\n")
    res = AgentRuleLint.check(dir; paths = ["test"])
    ok = any(
        d -> d.rule_id == "test-integrity" && occursin("exit", d.message),
        res.violations,
    )
    exit(ok ? 0 : 2)
finally
    rm(dir, recursive = true, force = true)
end
