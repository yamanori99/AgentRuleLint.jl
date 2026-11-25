include("mutation_lib.jl")

run_source_mutation(;
    name = "test-integrity exit in driver",
    rel_path = "src/rules/test_integrity.jl",
    needle = "elseif track_exit && s == \"call\" && _is_exit_call(node, source, pos)",
    replacement = "elseif false && track_exit && s == \"call\" && _is_exit_call(node, source, pos)",
    verify = root -> begin
        cmd = _julia_project_cmd(root, "test/test_integrity_mutation_exit.jl")
        return detector_disabled(cmd; dir = root)
    end,
)
