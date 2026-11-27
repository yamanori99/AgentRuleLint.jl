function _git_isolation_child_script(helpers_path::AbstractString)
    return """
    using AgentRuleLint
    include($(repr(helpers_path)))
    AgentRuleLint.git_run_scope() do
        hostile = mktempdir()
        dir = mktempdir()
        try
            rename_diff_literal_isolation_fixture(dir)
            hostile_renames_global_gitconfig!(hostile)
            base = GIT_ISOLATION_DIFF_BASE
            clean = git_check_isolation_signature(dir, base, mktempdir())
            hostile_sig = git_check_isolation_signature(dir, base, hostile)
            clean == hostile_sig || exit(42)
            exit(0)
        finally
            rm(hostile, recursive = true, force = true)
            rm(dir, recursive = true, force = true)
        end
    end
    """
end

@testset "isolated git ignores hostile global diff.renames (child HOME)" begin
    helpers = joinpath(@__DIR__, "git_test_helpers.jl")
    script = _git_isolation_child_script(helpers)
    cmd = Cmd(
        [
            joinpath(Sys.BINDIR, Base.julia_exename()),
            "--compiled-modules=existing",
            "--startup-file=no",
            "--project=$(ROOT)",
            "-e",
            script,
        ],
    )
    proc = run(ignorestatus(setenv(cmd; dir = @__DIR__)))
    @test proc.exitcode == 0
end

@testset "plain check on non-repository fails closed for manifest-sync" begin
    dir = mktempdir()
    try
        err = try
            AgentRuleLint.check(dir)
            nothing
        catch e
            e
        end
        @test err isa AgentRuleLint.GitError
        @test occursin("manifest-sync", AgentRuleLint.sprint(showerror, err))
    finally
        rm(dir, recursive = true, force = true)
    end
end
