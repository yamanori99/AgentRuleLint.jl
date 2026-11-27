include("mutation_lib.jl")

run_source_mutation(;
    name = "diff rename numstat skip bypass",
    rel_path = "src/diff.jl",
    needle = "if !text_binary && (stats.new_sum != add || stats.old_sum != del)",
    replacement = """
    skip_rename_numstat = add == 0 && del == 0 && _diff_has_content_delta(body)
            if !text_binary && !skip_rename_numstat && (stats.new_sum != add || stats.old_sum != del)
    """,
    verify = root -> begin
        script = raw"""
        using AgentRuleLint
        body = "@@ -1,1 +1,2 @@\n+line\n"
        try
            AgentRuleLint._changed_lines_from_diff_output(
                body,
                "0\t0\ttarget.jl\n",
                "0\t0\ttarget.jl\n",
                "target.jl",
            )
            exit(42)
        catch err
            err isa AgentRuleLint.GitError || rethrow(err)
            occursin("disagree with numstat", err.msg) || exit(42)
            exit(0)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
