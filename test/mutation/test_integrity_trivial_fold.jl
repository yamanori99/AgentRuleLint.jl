include("mutation_lib.jl")

run_source_mutation(;
    name = "test-integrity trivial @test folding",
    rel_path = "src/rules/test_integrity.jl",
    needle = "if fold_res == TEST_FOLD_TRIVIAL",
    replacement = "if false && fold_res == TEST_FOLD_TRIVIAL",
    verify = root -> begin
        cmd = _julia_project_cmd(root, "test/test_integrity_mutation_trivial.jl")
        return detector_disabled(cmd; dir = root)
    end,
)
