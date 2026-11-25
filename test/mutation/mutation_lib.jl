# Standalone mutation harness (not run from Pkg.test):
# copy the repo to a temp dir, patch the copy only, never write real `src/`.

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

function assert_real_src_clean(root::AbstractString = MUTATION_ROOT)
    status = read(`git -C $(root) status --porcelain -- src`, String)
    isempty(strip(status)) || error("real src/ is dirty after mutation harness:\n$status")
    return nothing
end

function run_source_mutation(;
        name::String,
        rel_path::AbstractString,
        needle::AbstractString,
        replacement::AbstractString,
        verify::Function,
    )
    real_path = joinpath(MUTATION_ROOT, String(rel_path))
    isfile(real_path) || error("$name: missing source $rel_path")
    orig = read(real_path, String)
    occursin(needle, orig) || error("$name: mutation needle missing in $rel_path")
    patched = replace(orig, needle => replacement; count = 1)
    patched == orig && error("$name: replacement left source unchanged")

    tmp = mktempdir()
    try
        cp(MUTATION_ROOT, tmp; force = true)
        path = joinpath(tmp, String(rel_path))
        isfile(path) || error("$name: missing source in temp copy $rel_path")
        write(path, patched)
        cmp_proc = run(ignorestatus(`cmp -s $real_path $path`))
        cmp_proc.exitcode == 0 && error("$name: cmp shows temp copy unchanged after mutation")
        real_status = read(`git -C $(MUTATION_ROOT) status --porcelain -- src`, String)
        isempty(strip(real_status)) || error("$name: real src/ dirty while mutating temp copy:\n$real_status")
        load_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e using\ AgentRuleLint`
        load_proc = run(ignorestatus(setenv(load_cmd; dir = tmp)))
        load_proc.exitcode != 0 && error("$name: using AgentRuleLint failed after mutation")
        verify(tmp) || error("$name: fail-closed check still passed after mutation")
        println("PASS: ", name)
    finally
        rm(tmp; recursive = true, force = true)
    end
    assert_real_src_clean()
    return nothing
end
