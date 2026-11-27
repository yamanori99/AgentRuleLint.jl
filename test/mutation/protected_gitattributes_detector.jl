# Detector for `.gitattributes` auto-protection: exit 0 = alive, exit 2 = disabled.

using AgentRuleLint

function main()
    dir = mktempdir()
    return try
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
            """,
        )
        write(joinpath(dir, "keep.jl"), "1\n")
        run(Cmd(["git", "-C", dir, "add", "-A"]))
        run(Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base"]))
        write(joinpath(dir, ".gitattributes"), "*.jl -diff\n")
        run(Cmd(["git", "-C", dir, "add", "-A"]))
        run(Cmd(["git", "-C", dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "attr"]))
        res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
        alive = res.exit_code == 1 &&
            any(d -> d.rule_id == "protected-paths" && d.path == ".gitattributes", res.violations)
        exit(alive ? 0 : 2)
    finally
        rm(dir, recursive = true, force = true)
    end
end

exit(main())
