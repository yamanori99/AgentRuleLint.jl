include("mutation_lib.jl")

run_source_mutation(;
    name = "diff hunk numstat sum cross-check",
    rel_path = "src/diff.jl",
    needle = "if stats.new_sum != add || stats.old_sum != del",
    replacement = "if false",
    verify = root -> begin
        script = raw"""
        using Test, AgentRuleLint
        body = "@@ -10,3 +10,1 @@\n"
        try
            AgentRuleLint._changed_lines_from_diff_output(
                body,
                "2\t3\ttarget.jl",
                "",
                "target.jl",
            )
            exit(1)
        catch err
            err isa AgentRuleLint.GitError || rethrow(err)
            occursin("path=target.jl", err.msg) || exit(1)
            exit(0)
        end
        """
        cmd = _julia_project_cmd(root, "-e", script)
        return !success(run(ignorestatus(setenv(cmd; dir = root))))
    end,
)
