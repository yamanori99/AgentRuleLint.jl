include("mutation_lib.jl")

run_source_mutation(;
    name = "silent-catch && interrupt propagation",
    rel_path = "src/syntax/try_catch_analysis.jl",
    needle = "    elseif kind(node) == KIf\n",
    replacement = "    elseif kind(node) == KAnd\n        return true # MUTATION\n    elseif kind(node) == KIf\n",
    verify = root -> begin
        cmd = _julia_project_cmd(
            root,
            "test/test_silent_catch_mutation_detector.jl",
            "silent_catch_and_only_interrupt.jl",
        )
        return detector_disabled(cmd; dir = root)
    end,
)
