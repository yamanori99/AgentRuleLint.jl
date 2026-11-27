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
        body = "@@ -10,3 +10,2 @@\n"
        try
            AgentRuleLint._changed_lines_from_diff_output(
                body,
                "1\t0\ttarget.jl",
                "1\t0\ttarget.jl",
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
        proc = run(ignorestatus(setenv(cmd; dir = root)))
        proc.exitcode != 0
    end,
)
