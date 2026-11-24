const _APP_ROOT = dirname(@__DIR__)
const _JULIA = joinpath(Sys.BINDIR, Base.julia_exename())

function _run_capture(cmd::Cmd)
    stdout = IOBuffer()
    stderr = IOBuffer()
    proc = run(ignorestatus(pipeline(cmd; stdout, stderr)), wait = true)
    return proc.exitcode, String(take!(stdout)), String(take!(stderr))
end

function _module_cmd(args::Vector{String})
    return Cmd(
        vcat(
            [_JULIA, "--startup-file=no", "--project=$_APP_ROOT", "-m", "AgentRuleLint"],
            args,
        ),
    )
end

@testset "Pkg app vs -m AgentRuleLint" begin
    args = ["check", "test/corpus"]

    cd(_APP_ROOT) do
        code_m, out_m, err_m = _run_capture(_module_cmd(args))
        code_cli = AgentRuleLint.cli_main(args)
        @test code_cli == code_m

        depot = mktempdir()
        develop = setenv(
            Cmd([_JULIA, "--startup-file=no", "-e", "using Pkg; Pkg.Apps.develop(path=ARGS[1])", _APP_ROOT]),
            "JULIA_DEPOT_PATH" => depot,
        )
        develop_proc = run(develop, wait = true)
        @test develop_proc.exitcode == 0

        app_bin = joinpath(depot, "bin", "agentrulelint")
        @test isfile(app_bin)

        app_cmd = setenv(Cmd(vcat([app_bin], args)), "JULIA_DEPOT_PATH" => depot)
        code_app, out_app, err_app = _run_capture(app_cmd)

        @test code_app == code_m
        @test out_app == out_m
        @test err_app == err_m
    end
end
