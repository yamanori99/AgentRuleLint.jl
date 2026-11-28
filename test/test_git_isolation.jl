function _git_isolation_child_script(helpers_path::AbstractString)
    return """
    using AgentRuleLint
    include($(repr(helpers_path)))
    function git_isolation_check_outcome(dir, diff_base, home)
        try
            return git_isolation_check_result(dir, diff_base, home)
        catch err
            err isa InterruptException && rethrow()
            if err isa AgentRuleLint.GitError
                return (kind = :git_error, msg = err.msg)
            end
            rethrow()
        end
    end
    AgentRuleLint.git_run_scope() do
        hostile = mktempdir()
        dir = mktempdir()
        try
            rename_diff_literal_isolation_fixture(dir)
            hostile_attributes_global_gitconfig!(hostile)
            hostile_default_xdg_attributes_under_home!(hostile)
            base = GIT_ISOLATION_DIFF_BASE
            clean = git_isolation_check_outcome(dir, base, mktempdir())
            hostile_sig = git_isolation_check_outcome(dir, base, hostile)
            git_isolation_outcomes_equivalent(clean, hostile_sig) || exit(42)
            exit(0)
        finally
            rm(hostile, recursive = true, force = true)
            rm(dir, recursive = true, force = true)
        end
    end
    """
end

@testset "isolated git ignores hostile global attributesfile (child HOME)" begin
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
        @test_throws AgentRuleLint.GitError r"manifest-sync" AgentRuleLint.check(dir)
    finally
        rm(dir, recursive = true, force = true)
    end
end
