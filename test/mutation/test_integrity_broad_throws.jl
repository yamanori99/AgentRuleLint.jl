include("mutation_lib.jl")

run_source_mutation(;
    name = "test-integrity broad @test_throws",
    rel_path = "src/rules/test_integrity.jl",
    needle = "if !isempty(args) && _exception_type_too_broad(args[1], source, argpos[1])",
    replacement = "if false && !isempty(args) && _exception_type_too_broad(args[1], source, argpos[1])",
    verify = root -> begin
        cmd = `julia --compiled-modules=no --startup-file=no --project=$(root) test/test_integrity_mutation_broad_throws.jl`
        return detector_disabled(cmd; dir = root)
    end,
)
