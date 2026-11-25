# Standalone mutation harness (not run from Pkg.test): patch src/, verify failure, always restore.

const MUTATION_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

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
