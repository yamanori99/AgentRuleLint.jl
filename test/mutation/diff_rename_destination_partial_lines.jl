include("mutation_lib.jl")

run_source_mutation(;
    name = "diff rename destination partial lines only",
    rel_path = "src/diff.jl",
    needle = """
                    old_path = old_path,
                )
                _whole_destination_changed_lines(root, path)
            else
                git_diff_changed_lines(
    """,
    replacement = """
                    old_path = old_path,
                )
            else
                git_diff_changed_lines(
    """,
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
            write(joinpath(dir,".AgentRuleLint.jl.toml"), cfg)
            write(joinpath(dir,"old.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            commit!("base")
            run(Cmd(["git","-C",dir,"mv","old.jl","new.jl"]))
            commit!("rename")
            res = AgentRuleLint.check(dir; diff_base="HEAD^")
            res.exit_code == 1 || exit(1)
            any(d -> d.rule_id == "project/diff-literal" && d.path == "new.jl", res.violations) || exit(1)
            exit(0)
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
