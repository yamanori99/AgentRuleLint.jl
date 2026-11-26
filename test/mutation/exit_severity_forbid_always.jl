include("mutation_lib.jl")

run_source_mutation(;
    name = "exit_severity forbid-level always fails",
    rel_path = "src/exit_severity.jl",
    needle = "d.level == :forbid && return true",
    replacement = "false && return true",
    verify = root -> begin
        script = """
        using AgentRuleLint
        rel = joinpath(\"test\", \"corpus\", \"expect_empty_reason.jl\")
        r = AgentRuleLint.check(\$(repr(root)); paths=[rel], exit_severity=:forbid)
        isempty(filter(d -> d.level == :forbid, r.violations)) && exit(1)
        exit(r.exit_code == 1 ? 0 : 2)
        """
        cmd = _julia_project_cmd(root, script)
        return detector_disabled(cmd; dir = root)
    end,
)