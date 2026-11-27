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
        using Test, AgentRuleLint
        dir = mktempdir()
        try
            run(Cmd(["git","-C",dir,"init","-q","-b","main"]))
            run(Cmd(["git","-C",dir,"config","user.email","t@t"]))
            run(Cmd(["git","-C",dir,"config","user.name","t"]))
            function commit!(m)
                run(Cmd(["git","-C",dir,"add","-A"]))
                run(Cmd(["git","-C",dir,"-c","commit.gpgsign=false","commit","-q","-m",m]))
            end
            write(joinpath(dir,"src.jl"), "v=1\n")
            commit!("base")
            run(Cmd(["git","-C",dir,"mv","src.jl","dst.jl"]))
            write(joinpath(dir,"dst.jl"), "v=1\nx=2\n")
            commit!("rename-edit")
            scope = AgentRuleLint.build_diff_scope(dir, "HEAD^")
            lines = AgentRuleLint.diff_changed_lines(scope, "dst.jl")
            AgentRuleLint.diff_path_status(scope, "dst.jl") == 'R' || exit(2)
            length(lines) > 1 && exit(0)
            exit(1)
        catch
            exit(2)
        finally
            rm(dir, recursive=true, force=true)
        end
        """
        cmd = _julia_project_cmd(root, "-e", script)
        proc = run(ignorestatus(setenv(cmd; dir = root)))
        proc.exitcode != 0
    end,
)
