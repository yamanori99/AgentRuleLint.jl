# Shared helpers for rule detector mutation tests in Pkg.test (not mutation/run_all.jl).

const _MUTATION_JULIA = joinpath(Sys.BINDIR, Base.julia_exename())

"""Child exit when violations match; distinct from Julia's default `1` on load/crash."""
const _MUTATION_HITS_EXIT = 42

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
Run `script` in a child Julia with `project`; return `proc.exitcode`.
Successful no-hit checks use 0; hit scripts use `_MUTATION_HITS_EXIT` (42).
Julia's default exit 1 on crash/load error must not be asserted as a hit.
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
