# Shared helpers for rule detector mutation tests in Pkg.test (not mutation/run_all.jl).

const _MUTATION_JULIA = joinpath(Sys.BINDIR, Base.julia_exename())

function _mutation_child_cmd(project::AbstractString, script::AbstractString)
    return Cmd(
        [
            _MUTATION_JULIA,
            # existing avoids full precompile per spawn; stale AgentRuleLint .ji would
            # load unpatched rule code and mutation assertions fail rather than pass.
            "--compiled-modules=existing",
            "--startup-file=no",
            "--project=$(project)",
            "-e",
            script,
        ],
    )
end

"""
Run `script` in a child Julia with `project`; return `proc.exitcode` (crashes and
load errors are nonzero and are not treated as detector outcomes).
"""
function _mutation_child_exitcode(
        project::AbstractString,
        script::AbstractString;
        dir::AbstractString,
    )
    cmd = _mutation_child_cmd(project, script)
    proc = run(ignorestatus(setenv(cmd; dir = dir)))
    return proc.exitcode
end
