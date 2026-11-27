include("mutation_lib.jl")

run_source_mutation(;
    name = "diff unified drop rename -M",
    rel_path = "src/diff.jl",
    needle = "-M\",\n        \"--no-color\",",
    replacement = "\"--no-color\",",
    verify = root -> begin
        script = raw"""
        using AgentRuleLint
        dir = mktempdir()
        try
            run(Cmd(["git","-C",dir,"init","-q","-b","main"]))
            run(Cmd(["git","-C",dir,"config","user.email","t@t"]))
            run(Cmd(["git","-C",dir,"config","user.name","t"]))
            function commit!(m)
                run(Cmd(["git","-C",dir,"add","-A"]))
                run(Cmd(["git","-C",dir,"-c","commit.gpgsign=false","commit","-q","-m",m]))
            end
            write(joinpath(dir,"src.jl"), "v = 1\n")
            commit!("base")
            run(Cmd(["git","-C",dir,"mv","src.jl","dst.jl"]))
            write(joinpath(dir,"dst.jl"), "v = 1\nextra\n")
            commit!("edit")
            scope = AgentRuleLint.build_diff_scope(dir, "HEAD^")
            lines = AgentRuleLint.diff_changed_lines(scope, "dst.jl")
            lines == Set([2]) || exit(1)
            exit(0)
        finally
            rm(dir, recursive=true, force=true)
        end
        """
        cmd = _julia_project_cmd(root, "-e", script)
        proc = run(ignorestatus(setenv(cmd; dir = root)))
        proc.exitcode != 0
    end,
)
