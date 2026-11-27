include("mutation_lib.jl")

run_source_mutation(;
    name = "silent-catch isa-or-rethrow branch",
    rel_path = "src/syntax/try_catch_analysis.jl",
    needle = "    kind(node) != KOr && return false\n",
    replacement = "    return true # MUTATION\n    kind(node) != KOr && return false\n",
    verify = root -> begin
        cmd = _julia_project_cmd(
            root,
            "test/test_silent_catch_mutation_detector.jl",
            "silent_catch_or_true_evasion.jl",
        )
        return detector_disabled(cmd; dir = root)
    end,
)
