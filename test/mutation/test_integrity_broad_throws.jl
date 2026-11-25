include("mutation_lib.jl")

run_source_mutation(;
    name = "test-integrity broad @test_throws",
    rel_path = "src/rules/test_integrity.jl",
    needle = "if !isempty(args) && _exception_type_too_broad(args[1], source, argpos[1])",
    replacement = "if false && !isempty(args) && _exception_type_too_broad(args[1], source, argpos[1])",
    verify = root -> begin
        script = raw"""
        using AgentRuleLint
        r = AgentRuleLint.check("."; paths = [joinpath("test", "corpus", "test_integrity_broad_throws.jl")])
        exit(any(d -> d.rule_id == "test-integrity" && !d.suppressed, r.violations) ? 0 : 1)
        """
        cmd = `julia --compiled-modules=no --startup-file=no --project=$(root) -e $script`
        return !success(run(ignorestatus(setenv(cmd; dir = root))))
    end,
)
