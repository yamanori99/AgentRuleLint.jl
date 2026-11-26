include("mutation_lib.jl")

run_source_mutation(;
    name = "exit_severity forbid-level always fails",
    rel_path = "src/exit_severity.jl",
    needle = "    d.level == :forbid && return true\n    r = get(VIOLATION_EXIT_RANK, d.level, 0)\n    t = get(EXIT_SEVERITY_RANK, threshold, 1)\n    return r >= t",
    replacement = "    r = get(VIOLATION_EXIT_RANK, d.level, 0)\n    t = get(EXIT_SEVERITY_RANK, threshold, 1)\n    return r >= t && d.level != :forbid",
    verify = root -> begin
        script = """
        using AgentRuleLint
        rel = joinpath("test", "corpus", "expect_multiline_call.jl")
        r = AgentRuleLint.check($(repr(root)); paths=[rel], exit_severity=:warn)
        isempty(filter(d -> d.level == :forbid, r.violations)) && exit(1)
        exit(r.exit_code == 1 ? 0 : 2)
        """
        cmd = _julia_project_cmd(root, "-e", script)
        return detector_disabled(cmd; dir = root)
    end,
)