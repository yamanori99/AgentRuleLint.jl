include("mutation_lib.jl")

run_source_mutation(;
    name = "diff parser unknown status",
    rel_path = "src/diff.jl",
    needle = "throw(GitError(\"unknown git diff name-status '\$status'\"))",
    replacement = "continue",
    verify = root -> begin
        script = raw"""
        using Test, AgentRuleLint
        try
            AgentRuleLint._parse_diff_path_events_payload("X\0x\0")
            exit(1)
        catch err
            err isa AgentRuleLint.GitError || rethrow(err)
            exit(0)
        end
        """
        cmd = `julia --compiled-modules=no --startup-file=no --project=$(root) -e $script`
        return !success(run(ignorestatus(setenv(cmd; dir = root))))
    end,
)
