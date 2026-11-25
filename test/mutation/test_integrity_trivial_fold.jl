include("mutation_lib.jl")

run_source_mutation(;
    name = "test-integrity trivial @test folding",
    rel_path = "src/rules/test_integrity.jl",
    needle = "if fold_res == TEST_FOLD_TRIVIAL",
    replacement = "if false && fold_res == TEST_FOLD_TRIVIAL",
    verify = root -> begin
        script = raw"""
        using AgentRuleLint
        r = AgentRuleLint.check("."; paths = [joinpath("test", "corpus", "test_integrity_trivial_true.jl")])
        exit(any(d -> d.rule_id == "test-integrity" && !d.suppressed, r.violations) ? 0 : 1)
        """
        cmd = `julia --compiled-modules=no --startup-file=no --project=$(root) -e $script`
        return !success(run(ignorestatus(setenv(cmd; dir = root))))
    end,
)
