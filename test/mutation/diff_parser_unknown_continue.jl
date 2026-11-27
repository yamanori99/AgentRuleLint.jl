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
            exit(42)
        catch err
            err isa AgentRuleLint.GitError || rethrow(err)
            exit(0)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
