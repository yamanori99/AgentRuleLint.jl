include("mutation_lib.jl")

run_source_mutation(;
    name = "diff unified drop rename path pair",
    rel_path = "src/diff.jl",
    needle = "append!(args, _git_diff_path_args(path_status, path, old_path))",
    replacement = "push!(args, normalize_path(path))",
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
            ver = string(pkgversion(AgentRuleLint))
            cfg =
                "agentrulelint_version = \"=" * ver *
                "\"\n[[project_rules]]\nid = \"diff-literal\"\nlevel = \"deny\"\npaths = [\"**\"]\nforbid_literals = [\"FORBIDDEN_DIFF_TOKEN\"]\nintent = \"\"\ndo_not = \"\"\n"
            write(joinpath(dir, ".AgentRuleLintConfig.toml"), cfg)
            write(joinpath(dir,"src.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            commit!("base")
            run(Cmd(["git","-C",dir,"mv","src.jl","dst.jl"]))
            write(joinpath(dir,"dst.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\nedit\n")
            commit!("edit")
            res = AgentRuleLint.check(dir; diff_base="HEAD^")
            res.exit_code == 1 || exit(1)
            any(
                d -> d.rule_id == "project/diff-literal" && d.path == "dst.jl" &&
                    d.span.start_line == 1,
                res.violations,
            ) || exit(1)
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
