const _ON_FILTER_RULE = "protected-paths"

@testset "protected-paths paths[].on" begin
    RULE = _ON_FILTER_RULE

    function hits(res)
        return filter(
            d ->
            d.rule_id == RULE && !d.suppressed &&
                d.expect_status != :fulfilled && d.level != :allow,
            res.violations,
        )
    end

    function on_cfg(on_array::AbstractString, extra_glob::AbstractString = "guard/**")
        ver = string(pkgversion(AgentRuleLint))
        return """
        agentrulelint_version = \"=$(ver)\"

        [rules.protected-paths]
        level = \"forbid\"
        paths = [
          { glob = \"$extra_glob\", on = $on_array, reason = \"Guarded harness paths.\" },
        ]
        """
    end

    function load_guard_policy(dir, on_array)
        path = joinpath(dir, ".AgentRuleLint.jl.toml")
        write(path, on_cfg(on_array))
        return AgentRuleLint.load_policy(dir; config_path = path)
    end

    function event_hits(policy, ev::AgentRuleLint.DiffPathEvent)
        diags = AgentRuleLint._handle_protected_event("", "HEAD^1", ev, policy)
        return filter(d -> d.rule_id == RULE, diags)
    end

    @testset "config on empty, unknown, duplicate fail closed" begin
        ver = string(pkgversion(AgentRuleLint))
        root = mktempdir()
        try
            for (extra, fragment) in (
                    ("empty on", "on = []"),
                    ("unknown on", "on = [\"mystery\"]"),
                    ("duplicate on", "on = [\"deleted\", \"deleted\"]"),
                )
                cfg = """
                agentrulelint_version = \"=$(ver)\"
                [rules.protected-paths]
                level = \"forbid\"
                paths = [
                  { glob = \"x/**\", $fragment, reason = \"r\" },
                ]
                """
                write(joinpath(root, ".AgentRuleLint.jl.toml"), cfg)
                err = @test_throws AgentRuleLint.ConfigError AgentRuleLint.load_policy(root)
                @test occursin("rules.protected-paths.paths[1].on", sprint(showerror, err.value))
                @test AgentRuleLint.cli_main(["check", "--config", joinpath(root, ".AgentRuleLint.jl.toml")]) == 2
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "auto-protected path ignores paths[].on" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(
                joinpath(dir, ".AgentRuleLint.jl.toml"),
                on_cfg("[\"deleted\"]"),
            )
            write(joinpath(dir, ".JETLSConfig.toml"), "ok = true\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, ".JETLSConfig.toml"), "ok = false\n")
            git_commit_all!(dir, "change")
            cd(dir) do
                res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                jetls = filter(h -> h.path == ".JETLSConfig.toml", hits(res))
                @test length(jetls) == 1
                @test occursin("modified", first(jetls).message)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "on deleted and renamed only (integration)" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), on_cfg("[\"deleted\", \"renamed\"]"))
            mkpath(joinpath(dir, "guard"))
            write(joinpath(dir, "guard", "keep.jl"), "1\n")
            git_commit_all!(dir, "base")

            @testset "added allowed" begin
                write(joinpath(dir, "guard", "new.jl"), "2\n")
                git_commit_all!(dir, "add")
                cd(dir) do
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    @test !any(h -> startswith(h.path, "guard/"), hits(res))
                end
            end

            @testset "modified allowed" begin
                write(joinpath(dir, "guard", "keep.jl"), "3\n")
                git_commit_all!(dir, "mod")
                cd(dir) do
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    @test !any(h -> h.path == "guard/keep.jl", hits(res))
                end
            end

            @testset "deleted forbidden" begin
                rm(joinpath(dir, "guard", "keep.jl"))
                git_commit_all!(dir, "del")
                cd(dir) do
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    h = filter(x -> x.path == "guard/keep.jl", hits(res))
                    @test length(h) == 1
                    @test occursin("deleted", first(h).message)
                end
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "rename rows with on deleted and renamed" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), on_cfg("[\"deleted\", \"renamed\"]"))
            mkpath(joinpath(dir, "guard"))
            mkpath(joinpath(dir, "outside"))
            write(joinpath(dir, "guard", "in.jl"), "a\n")
            write(joinpath(dir, "outside", "ext.jl"), "b\n")
            git_commit_all!(dir, "base")

            @testset "rename out of glob is deleted on old path" begin
                run_git_cmd(dir, "mv", "guard/in.jl", "outside/in.jl"; cwd = dir)
                git_commit_all!(dir, "rename out")
                cd(dir) do
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    h = filter(x -> x.path == "guard/in.jl", hits(res))
                    @test length(h) == 1
                    @test occursin("deleted", first(h).message)
                end
            end

            write(joinpath(dir, "guard", "back.jl"), "c\n")
            git_commit_all!(dir, "restore guard")

            @testset "rename into glob is added only (allowed)" begin
                write(joinpath(dir, "outside", "ext.jl"), "b\n")
                run_git_cmd(dir, "mv", "outside/ext.jl", "guard/ext.jl"; cwd = dir)
                git_commit_all!(dir, "rename in")
                cd(dir) do
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    @test !any(h -> h.path == "guard/ext.jl", hits(res))
                end
            end

            @testset "rename within glob is renamed" begin
                write(joinpath(dir, "guard", "back.jl"), "c\n")
                run_git_cmd(dir, "mv", "guard/back.jl", "guard/renamed.jl"; cwd = dir)
                git_commit_all!(dir, "rename within")
                cd(dir) do
                    res = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                    paths = Set(h.path for h in hits(res))
                    @test "guard/back.jl" in paths || "guard/renamed.jl" in paths
                    renamed = filter(h -> occursin("renamed", h.message), hits(res))
                    @test !isempty(renamed)
                end
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "copy rows (synthetic diff events)" begin
        dir = abspath(mktempdir())
        try
            all_on = "[\"added\", \"modified\", \"deleted\", \"renamed\", \"copied\"]"
            policy = load_guard_policy(dir, all_on)

            @testset "only source matches: no finding" begin
                ev = AgentRuleLint.DiffPathEvent('C', "outside/dup.jl", "guard/src.jl")
                @test isempty(event_hits(policy, ev))
            end

            @testset "only destination matches: added" begin
                ev = AgentRuleLint.DiffPathEvent('C', "guard/dup.jl", "outside/src.jl")
                h = event_hits(policy, ev)
                @test length(h) == 1
                @test h[1].path == "guard/dup.jl"
                @test occursin("added", h[1].message)
            end

            @testset "both match: copied on destination only" begin
                ev = AgentRuleLint.DiffPathEvent('C', "guard/dst.jl", "guard/src.jl")
                h = event_hits(policy, ev)
                @test length(h) == 1
                @test h[1].path == "guard/dst.jl"
                @test occursin("copied", h[1].message)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "added modified deleted words with full on" begin
        dir = abspath(mktempdir())
        try
            all_on = "[\"added\", \"modified\", \"deleted\", \"renamed\", \"copied\"]"
            policy = load_guard_policy(dir, all_on)
            for (st, old_p, new_p, path, word) in (
                    ('A', "", "guard/a.jl", "guard/a.jl", "added"),
                    ('M', "", "guard/m.jl", "guard/m.jl", "modified"),
                    ('D', "", "guard/d.jl", "guard/d.jl", "deleted"),
                )
                ev = AgentRuleLint.DiffPathEvent(st, new_p, old_p)
                h = event_hits(policy, ev)
                @test length(h) == 1
                @test h[1].path == path
                @test occursin(word, h[1].message)
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
