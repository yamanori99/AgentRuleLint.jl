# Shared helpers for rule detector mutation tests in Pkg.test (not mutation/run_all.jl).

const _MUTATION_JULIA = joinpath(Sys.BINDIR, Base.julia_exename())

function _mutation_child_cmd(project::AbstractString, script::AbstractString)
    return Cmd(
        [
            _MUTATION_JULIA,
            "--compiled-modules=existing",
            "--startup-file=no",
            "--project=$(project)",
            "-e",
            script,
        ],
    )
end

"""
Run `script` in a child Julia with `project`; return whether the process succeeded (exit 0).
"""
function _mutation_child_ok(project::AbstractString, script::AbstractString; dir::AbstractString)
    cmd = _mutation_child_cmd(project, script)
    return success(run(ignorestatus(setenv(cmd; dir = dir))))
end
