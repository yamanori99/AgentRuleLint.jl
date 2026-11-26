include("mutation_lib.jl")

run_source_mutation(;
    name = "silent-catch reachability branch",
    rel_path = "src/syntax/try_catch_analysis.jl",
    needle = "        _stmt_unconditional_return(stmt) && (reachable = false)\n",
    replacement = "        # MUTATION reachable\n",
    verify = root -> begin
        cmd = _julia_project_cmd(
            root,
            "test/test_silent_catch_mutation_detector.jl",
            "silent_catch_dead_rethrow.jl",
        )
        return detector_disabled(cmd; dir = root)
    end,
)
