# Standalone mutation harness (not run from Pkg.test): patch src/, verify failure, always restore.

const MUTATION_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

"""
Run a detector helper with a strict exit contract:

- 0 → finding still present (detector alive) → return false
- 2 → finding absent (detector disabled) → return true
- anything else (including Julia's usual 1 on uncaught errors) → harness failure

Do not use exit 1 for "disabled": that collides with ProcessExited(1) from crashes.
"""
function detector_disabled(cmd::Cmd; dir::AbstractString = MUTATION_ROOT)
    proc = run(ignorestatus(setenv(cmd; dir = dir)))
    code = proc.exitcode
    code == 2 && return true
    code == 0 && return false
    error("detector helper crashed with exit $code (expected 0=alive or 2=disabled): $cmd")
end

function run_source_mutation(;
        name::String,
        rel_path::AbstractString,
        needle::AbstractString,
        replacement::AbstractString,
        verify::Function,
    )
    path = joinpath(MUTATION_ROOT, String(rel_path))
    isfile(path) || error("$name: missing source $rel_path")
    orig = read(path, String)
    occursin(needle, orig) || error("$name: mutation needle missing in $rel_path")
    bak = path * ".mutation_bak"
    cp(path, bak; force = true)
    patched = replace(orig, needle => replacement, count = 1)
    patched == orig && error("$name: replacement left source unchanged")
    write(path, patched)
    try
        cmp_proc = run(ignorestatus(`cmp -s $bak $path`))
        cmp_proc.exitcode == 0 && error("$name: cmp shows file unchanged after mutation")
        load_cmd = `julia --compiled-modules=no --startup-file=no --project=$(MUTATION_ROOT) -e using\ AgentRuleLint`
        load_proc = run(ignorestatus(setenv(load_cmd; dir = MUTATION_ROOT)))
        load_proc.exitcode != 0 && error("$name: using AgentRuleLint failed after mutation")
        verify(MUTATION_ROOT) || error("$name: fail-closed check still passed after mutation")
        println("PASS: ", name)
    finally
        if isfile(bak)
            cp(bak, path; force = true)
            rm(bak; force = true)
        end
    end
    return nothing
end
