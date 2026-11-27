const _APP_ROOT = dirname(@__DIR__)
const _JULIA = joinpath(Sys.BINDIR, Base.julia_exename())
const _PROJECT_TOML = joinpath(_APP_ROOT, "Project.toml")
function _run_capture(cmd::Cmd)
    stdout = IOBuffer()
    stderr = IOBuffer()
    proc = run(ignorestatus(pipeline(cmd; stdout, stderr)), wait = true)
    return proc.exitcode, String(take!(stdout)), String(take!(stderr))
end

# Discard one child run so measured stdout/stderr are not polluted by Julia's
# package precompile progress (see `Base.precompilepkgs` in Julia `precompilation.jl`,
# which writes summary lines such as "Precompiling …" to `io`, defaulting to `stderr`).
function _warmup_capture(cmd::Cmd)
    code, _, _ = _run_capture(cmd)
    return code
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
    manifest = joinpath(root, "Manifest.toml")
    isfile(manifest) && cp(manifest, joinpath(pkg_dir, "Manifest.toml"))
    cp(joinpath(root, "src"), joinpath(pkg_dir, "src"))
    return staging, pkg_dir
end

function _seed_depot_for_offline_apps!(dst_depot::String, src_depot::String)
    for sub in ("registries", "clones", "packages")
        src = joinpath(src_depot, sub)
        isdir(src) || continue
        cp(src, joinpath(dst_depot, sub); force = true)
    end
    return nothing
end

@testset "Pkg app vs -m AgentRuleLint" begin
    args = ["check", "test/corpus"]
    project_toml_before = read(_PROJECT_TOML)

    cd(_APP_ROOT) do
        module_cmd = _module_cmd(args)
        code_warm_m = _warmup_capture(module_cmd)
        code_m, out_m, err_m = _run_capture(module_cmd)
        @test code_warm_m == code_m
        code_cli = AgentRuleLint.cli_main(args)
        @test code_cli == code_m

        staging_root = ""
        depot = mktempdir()
        try
            _, staging_root = _stage_package_for_apps_develop(_APP_ROOT)
            _seed_depot_for_offline_apps!(depot, first(DEPOT_PATH))
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
                "JULIA_PKG_OFFLINE" => "true",
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
            code_warm_app = _warmup_capture(app_cmd)
            code_app, out_app, err_app = _run_capture(app_cmd)
            @test code_warm_app == code_app

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
