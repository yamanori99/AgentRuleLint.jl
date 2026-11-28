# Exit contract: 0 = detector alive, 2 = disabled (do not use 1; harness treats 1 as crash).

using AgentRuleLint

const run_git_cmd = AgentRuleLint.run_git_cmd

function main()
    return AgentRuleLint.git_run_scope() do
        return _protected_paths_on_filter_detector_body()
    end
end

function _protected_paths_on_filter_detector_body()
    dir = mktempdir()
    return try
        run_git_cmd(dir, "init", "-q", "-b", "main"; cwd = dir)
        run_git_cmd(dir, "config", "user.email", "mut@test"; cwd = dir)
        run_git_cmd(dir, "config", "user.name", "mut"; cwd = dir)
        ver = string(pkgversion(AgentRuleLint))
        write(
            joinpath(dir, ".AgentRuleLint.jl.toml"),
            """
            agentrulelint_version = \"=$(ver)\"

            [rules.protected-paths]
            level = \"forbid\"
            paths = [
              { glob = \"harness/**\", on = [\"deleted\"], reason = \"Harness deletion guard.\" },
            ]
            """,
        )
        mkpath(joinpath(dir, "harness"))
        write(joinpath(dir, "harness", "t.jl"), "1\n")
        run_git_cmd(dir, "add", "-A"; cwd = dir)
        run_git_cmd(dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base"; cwd = dir)
        rm(joinpath(dir, "harness", "t.jl"))
        run_git_cmd(dir, "add", "-A"; cwd = dir)
        run_git_cmd(dir, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "del"; cwd = dir)
        res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
        alive = res.exit_code == 1 &&
            any(d -> d.rule_id == "protected-paths" && d.path == "harness/t.jl", res.violations)
        exit(alive ? 0 : 2)
    finally
        rm(dir, recursive = true, force = true)
    end
end

exit(main())
