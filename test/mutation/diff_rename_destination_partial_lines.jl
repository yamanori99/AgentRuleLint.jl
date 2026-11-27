include("mutation_lib.jl")

const _DETECT = _MUTATION_VERIFY_DETECTED_EXIT

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
        script = """
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
            res.exit_code == 1 || exit($_DETECT)
            any(d -> d.rule_id == "project/diff-literal" && d.path == "new.jl", res.violations) || exit($_DETECT)
            exit(0)
        finally
            rm(dir, recursive=true, force=true)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)