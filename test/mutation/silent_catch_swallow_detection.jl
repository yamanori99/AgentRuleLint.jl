include("mutation_lib.jl")

run_source_mutation(;
    name = "silent-catch empty swallow detection",
    rel_path = "src/syntax/try_catch_analysis.jl",
    needle = "    isempty(stmts) && return true\n",
    replacement = "    return false # MUTATION\n    isempty(stmts) && return true\n",
    verify = root -> begin
        cmd = _julia_project_cmd(
            root,
            "test/test_silent_catch_mutation_detector.jl",
            "silent_catch_empty.jl",
        )
        return detector_disabled(cmd; dir = root)
    end,
)
