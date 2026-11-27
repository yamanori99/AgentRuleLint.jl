# Detector for diff hardening mutations: exit 0 = loud failure (detector alive), exit 2 = silent pass (disabled).

using AgentRuleLint

function main()
    dir = mktempdir()
    try
        run(Cmd(["git", "-C", dir, "init", "-q", "-b", "main"]))
        run(Cmd(["git", "-C", dir, "config", "user.email", "mut@test"]))
        run(Cmd(["git", "-C", dir, "config", "user.name", "mut"]))
        ver = string(pkgversion(AgentRuleLint))
        write(
            joinpath(dir, ".AgentRuleLintConfig.toml"),
            """
            agentrulelint_version = \"=$(ver)\"

            [rules.protected-paths]
            level = \"forbid\"

            [[project_rules]]
            id = \"diff-literal\"
            level = \"deny\"
            paths = [\"**\"]
            forbid_literals = [\"FORBIDDEN_DIFF_TOKEN\"]
            intent = \"\"
            do_not = \"\"
            """,
        )
        write(joinpath(dir, "target.jl"), "x = 1\n")
        run(Cmd(["git", "-C", dir, "add", "-A"]))
        run(Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base"]))
        write(joinpath(dir, ".gitattributes"), "*.jl -diff\n")
        write(joinpath(dir, "target.jl"), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
        run(Cmd(["git", "-C", dir, "add", "-A"]))
        run(Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "head"]))
        loud = try
            res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
            has_literal = any(d -> d.rule_id == "project/diff-literal", res.violations)
            has_prot = any(d -> d.rule_id == "protected-paths" && d.path == ".gitattributes", res.violations)
            res.exit_code != 0 || (has_literal && has_prot)
        catch err
            err isa AgentRuleLint.GitError
        end
        exit(loud ? 0 : 2)
    finally
        rm(dir, recursive = true, force = true)
    end
end

exit(main())