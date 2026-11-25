include("mutation_lib.jl")

run_source_mutation(;
    name = "test-integrity tolerance loosening",
    rel_path = "src/rules/test_integrity.jl",
    needle = "loosen = _tol_grew(base.atol, snap.atol) || _tol_grew(base.rtol, snap.rtol)",
    replacement = "loosen = false",
    verify = root -> begin
        cmd = `julia --compiled-modules=no --startup-file=no --project=$(root) test/test_integrity_mutation_tol.jl`
        return !success(run(ignorestatus(setenv(cmd; dir = root))))
    end,
)
