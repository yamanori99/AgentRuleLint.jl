using AgentRuleLint
using Test

@testset "config rename fail-closed" begin
    function minimal_config(extra::AbstractString = "")
        v = string(pkgversion(AgentRuleLint))
        return """
        agentrulelint_version = \"=$(v)\"
        $extra
        """
    end

    function expect_rename_config_error(f)
        try
            f()
            @test false
            return nothing
        catch err
            if err isa AgentRuleLint.ConfigError
                return err
            else
                rethrow(err)
            end
        end
    end

    function assert_rename_error(err)
        @test err isa AgentRuleLint.ConfigError
        msg = sprint(showerror, err)
        @test occursin(AgentRuleLint.LEGACY_CONFIG_FILENAME, msg)
        @test occursin(AgentRuleLint.CONFIG_FILENAME, msg)
        @test occursin("git mv", msg)
        return true
    end

    @testset "discovers new config filename" begin
        root = mktempdir()
        try
            write(joinpath(root, AgentRuleLint.CONFIG_FILENAME), minimal_config())
            write(joinpath(root, "ok.jl"), "1\n")
            res = AgentRuleLint.check(root; paths = ["ok.jl"])
            @test res.config_source.path == AgentRuleLint.CONFIG_FILENAME
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "legacy config alone fails" begin
        root = mktempdir()
        try
            write(joinpath(root, AgentRuleLint.LEGACY_CONFIG_FILENAME), minimal_config())
            err = expect_rename_config_error(() -> AgentRuleLint.check(root))
            @test assert_rename_error(err)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "both config names fail" begin
        root = mktempdir()
        try
            write(joinpath(root, AgentRuleLint.LEGACY_CONFIG_FILENAME), minimal_config())
            write(joinpath(root, AgentRuleLint.CONFIG_FILENAME), minimal_config())
            err = expect_rename_config_error(() -> AgentRuleLint.check(root))
            @test assert_rename_error(err)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config-from ref with only legacy fails" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, AgentRuleLint.LEGACY_CONFIG_FILENAME), minimal_config())
            write(joinpath(dir, "ok.jl"), "1\n")
            git_commit_all!(dir, "base")
            err = expect_rename_config_error(
                () -> AgentRuleLint.check(dir; config_from = "HEAD", paths = ["ok.jl"]),
            )
            @test assert_rename_error(err)
        finally
            rm(dir, recursive = true, force = true)
        end
    end

    @testset "init refuses legacy file present" begin
        root = mktempdir()
        try
            write(joinpath(root, AgentRuleLint.LEGACY_CONFIG_FILENAME), minimal_config())
            cd(root) do
                @test AgentRuleLint.cli_main(["init"]) == 2
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "init writes header comment" begin
        root = mktempdir()
        try
            cd(root) do
                @test AgentRuleLint.cli_main(["init"]) == 0
            end
            body = read(joinpath(root, AgentRuleLint.CONFIG_FILENAME), String)
            @test startswith(body, AgentRuleLint.CONFIG_FILE_HEADER)
        finally
            rm(root, recursive = true, force = true)
        end
    end
end
