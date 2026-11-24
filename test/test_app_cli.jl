const _APP_ROOT = dirname(@__DIR__)
const _JULIA = joinpath(Sys.BINDIR, Base.julia_exename())
const _PROJECT_TOML = joinpath(_APP_ROOT, "Project.toml")
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

function _stage_package_for_apps_develop(root::String)
    staging = mktempdir()
    pkg_dir = joinpath(staging, "AgentRuleLint")
    mkpath(pkg_dir)
    cp(joinpath(root, "Project.toml"), joinpath(pkg_dir, "Project.toml"))
    cp(joinpath(root, "src"), joinpath(pkg_dir, "src"))
    return staging, pkg_dir
end

@testset "Pkg app vs -m AgentRuleLint" begin
    args = ["check", "test/corpus"]
    project_toml_before = read(_PROJECT_TOML)

    cd(_APP_ROOT) do
        code_m, out_m, err_m = _run_capture(_module_cmd(args))
        code_cli = AgentRuleLint.cli_main(args)
        @test code_cli == code_m

        staging_root = ""
        depot = mktempdir()
        try
            _, staging_root = _stage_package_for_apps_develop(_APP_ROOT)
            develop = addenv(
                Cmd(
                    [
                        _JULIA,
                        "--startup-file=no",
                        "-e",
                        "using Pkg; Pkg.Apps.develop(path=ARGS[1])",
                        staging_root,
                    ]
                ),
                "JULIA_DEPOT_PATH" => depot,
                "JULIA_LOAD_PATH" => "@:@stdlib",
            )
            develop_proc = run(ignorestatus(develop), wait = true)
            @test develop_proc.exitcode == 0

            app_bin = joinpath(depot, "bin", "agentrulelint")
            @test isfile(app_bin)

            app_cmd = addenv(
                Cmd(vcat([app_bin], args)),
                "JULIA_DEPOT_PATH" => depot,
                "JULIA_LOAD_PATH" => "@:@stdlib",
            )
            code_app, out_app, err_app = _run_capture(app_cmd)

            @test code_app == code_m
            @test out_app == out_m
            @test err_app == err_m
        finally
            if !isempty(staging_root)
                rm(dirname(staging_root); recursive = true, force = true)
            end
            rm(depot; recursive = true, force = true)
        end
    end

    @test read(_PROJECT_TOML) == project_toml_before
end
