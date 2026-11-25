include("mutation_lib.jl")

run_source_mutation(;
    name = "explain default_policy fallback",
    rel_path = "src/format/report.jl",
    needle = "policy = resolve_policy(root)",
    replacement = "policy = try resolve_policy(root) catch; default_policy(root) end",
    verify = root -> begin
        cmd = `julia --compiled-modules=no --startup-file=no --project=$(root) test/test_explain_invalid_config.jl`
        return !success(run(ignorestatus(setenv(cmd; dir = root))))
    end,
)
