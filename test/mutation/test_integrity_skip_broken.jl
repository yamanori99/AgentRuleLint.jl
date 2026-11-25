include("mutation_lib.jl")

run_source_mutation(;
    name = "test-integrity skip/broken count increase",
    rel_path = "src/rules/test_integrity.jl",
    needle = "for m in _SKIP_BROKEN_MACROS\n        get(counts, m, 0) <= get(base_counts, m, 0) && continue",
    replacement = "for m in ()\n        get(counts, m, 0) <= get(base_counts, m, 0) && continue",
    verify = root -> begin
        cmd = `julia --compiled-modules=no --startup-file=no --project=$(root) test/test_integrity_mutation_skip.jl`
        return !success(run(ignorestatus(setenv(cmd; dir = root))))
    end,
)
