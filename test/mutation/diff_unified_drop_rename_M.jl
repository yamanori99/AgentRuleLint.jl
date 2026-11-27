include("mutation_lib.jl")
using AgentRuleLint

const _DETECT = _MUTATION_VERIFY_DETECTED_EXIT

run_source_mutation(;
    name = "diff unified drop rename path pair",
    rel_path = "src/diff.jl",
    needle = "append!(args, _git_diff_path_args(path_status, path, old_path))",
    replacement = "push!(args, normalize_path(path))",
    verify = root -> begin
        cfg_file = repr(AgentRuleLint.CONFIG_FILENAME)
        script = """
        using AgentRuleLint
        dir = mktempdir()
        try
            AgentRuleLint.run_git_cmd(dir, "init", "-q", "-b", "main"; cwd = dir)
            AgentRuleLint.run_git_cmd(dir, "config", "user.email", "t@t"; cwd = dir)
            AgentRuleLint.run_git_cmd(dir, "config", "user.name", "t"; cwd = dir)
            function commit!(m)
                AgentRuleLint.run_git_cmd(dir, "add", "-A"; cwd = dir)
                AgentRuleLint.run_git_cmd(dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", m; cwd = dir)
            end
            ver = string(pkgversion(AgentRuleLint))
            cfg =
                "agentrulelint_version = \\\"=" * ver *
                "\\\"\\n[[project_rules]]\\nid = \\\"diff-literal\\\"\\nlevel = \\\"deny\\\"\\npaths = [\\\"**\\\"]\\nforbid_literals = [\\\"FORBIDDEN_DIFF_TOKEN\\\"]\\nintent = \\\"\\\"\\ndo_not = \\\"\\\"\\n"
            write(joinpath(dir, $cfg_file), cfg)
            write(joinpath(dir,"src.jl"), "x = \\\"FORBIDDEN_DIFF_TOKEN\\\"\\n")
            commit!("base")
            AgentRuleLint.run_git_cmd(dir, "mv", "src.jl", "dst.jl"; cwd = dir)
            write(joinpath(dir,"dst.jl"), "x = \\\"FORBIDDEN_DIFF_TOKEN\\\"\\nedit\\n")
            commit!("edit")
            try
                res = AgentRuleLint.check(dir; diff_base="HEAD^")
                res.exit_code == 1 || exit($_DETECT)
                any(
                    d -> d.rule_id == "project/diff-literal" && d.path == "dst.jl" &&
                        d.span.start_line == 1,
                    res.violations,
                ) || exit($_DETECT)
                exit(0)
            catch err
                err isa AgentRuleLint.GitError || rethrow(err)
                exit($_DETECT)
            end
        finally
            rm(dir, recursive=true, force=true)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
