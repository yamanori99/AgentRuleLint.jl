include("mutation_lib.jl")

run_source_mutation(;
    name = "test-integrity runtests include removal",
    rel_path = "src/rules/test_integrity.jl",
    needle = "for ek in base_entries",
    replacement = "for ek in ()",
    verify = root -> begin
        cmd = `julia --compiled-modules=no --startup-file=no --project=$(root) test/test_integrity_mutation_runtests.jl`
        return !success(run(ignorestatus(setenv(cmd; dir = root))))
    end,
)
