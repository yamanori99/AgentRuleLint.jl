# Standalone mutation harness (not run from Pkg.test):
# copy the repo to a temp dir, patch the copy only, never write real `src/`.

const MUTATION_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

"""Child exit when a verify script signals mutation detected (distinct from Julia's default `1` on crash)."""
const _MUTATION_VERIFY_DETECTED_EXIT = 42  # same contract as `_MUTATION_HITS_EXIT` in mutation_subprocess_helpers.jl

"""Mutation applied but fail-closed / detector check still green (survived)."""
struct MutationSurvived <: Exception
    msg::String
end

"""Verify subprocess exited with a code other than 0 or `_MUTATION_VERIFY_DETECTED_EXIT`."""
struct MutationVerifyCrashed <: Exception
    msg::String
end

Base.showerror(io::IO, e::MutationSurvived) = print(io, e.msg)
Base.showerror(io::IO, e::MutationVerifyCrashed) = print(io, e.msg)

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

function assert_detector_alive(cmd::Cmd; dir::AbstractString = MUTATION_ROOT)
    proc = run(ignorestatus(setenv(cmd; dir = dir)))
    proc.exitcode == 0 ||
        error("detector not alive (expected exit 0, got $(proc.exitcode)): $cmd")
    return true
end

function assert_real_src_clean(root::AbstractString = MUTATION_ROOT)
    status = read(`git -C $(root) status --porcelain -- src`, String)
    isempty(strip(status)) || error("real src/ is dirty after mutation harness:\n$status")
    return nothing
end

"""
Run a verify subprocess with a strict exit contract:

- `0` → mutation not detected (protection still holds) → return `false`
- `_MUTATION_VERIFY_DETECTED_EXIT` (42) → mutation detected → return `true`
- any other code (including Julia's default `1` on parse/load/uncaught errors) → harness crash
"""
function mutation_verify_detected(cmd::Cmd; dir::AbstractString)
    proc = run(ignorestatus(setenv(cmd; dir = dir)))
    sig = proc.termsignal
    code = proc.exitcode
    if sig != 0
        throw(
            MutationVerifyCrashed(
                "verify subprocess terminated by signal $sig (exit $code): $cmd",
            ),
        )
    end
    code == 0 && return false
    code == _MUTATION_VERIFY_DETECTED_EXIT && return true
    throw(
        MutationVerifyCrashed(
            "verify subprocess crashed with exit $code " *
                "(expected 0=not detected or $(_MUTATION_VERIFY_DETECTED_EXIT)=detected): $cmd",
        ),
    )
end

function mutation_verify_script(project::AbstractString, script::AbstractString; dir::AbstractString)
    cmd = _julia_project_cmd(project, "-e", script)
    return mutation_verify_detected(cmd; dir = dir)
end

function mutation_verify_driver(project::AbstractString, rel_script::AbstractString; dir::AbstractString)
    cmd = _julia_project_cmd(project, rel_script)
    return mutation_verify_detected(cmd; dir = dir)
end

function _julia_project_cmd(project::AbstractString, args::AbstractString...)
    # Same interpreter as this process; avoid bare `julia` on PATH.
    return Cmd(
        [
            Base.julia_cmd().exec...,
            "--compiled-modules=no",
            "--startup-file=no",
            "--project=$(project)",
            args...,
        ],
    )
end

function run_source_mutation(;
        name::String,
        rel_path::AbstractString,
        needle::AbstractString,
        replacement::AbstractString,
        verify::Function,
        replace_count::Integer = 1,
        extra_patches::Vector{Pair{String, String}} = Pair{String, String}[],
    )
    try
        real_path = joinpath(MUTATION_ROOT, String(rel_path))
        isfile(real_path) || error("$name: missing source $rel_path")
        orig = read(real_path, String)
        occursin(needle, orig) || error("$name: mutation needle missing in $rel_path")
        # Default replace_count=1 keeps single-site mutations precise; pass a
        # larger value (or typemax(Int)) when every matching call site must be
        # patched (e.g. both explain resolve_policy sites after #83).
        patched = replace(orig, needle => replacement; count = Int(replace_count))
        patched == orig && error("$name: replacement left source unchanged")
        if replace_count > 1
            n = count(replacement, patched)
            n < 2 && error("$name: expected ≥2 replacement sites, found $n")
        end
        for (extra_needle, extra_replacement) in extra_patches
            occursin(extra_needle, patched) ||
                error("$name: extra patch needle missing in $rel_path")
            next = replace(patched, extra_needle => extra_replacement; count = Int(replace_count))
            next == patched && error("$name: extra patch left source unchanged")
            patched = next
        end

        tmp = mktempdir()
        try
            cp(MUTATION_ROOT, tmp; force = true)
            path = joinpath(tmp, String(rel_path))
            isfile(path) || error("$name: missing source in temp copy $rel_path")
            real_status = read(`git -C $(MUTATION_ROOT) status --porcelain -- src`, String)
            isempty(strip(real_status)) ||
                error("$name: real src/ dirty while mutating temp copy:\n$real_status")
            if verify(tmp)
                error("$name: verify is vacuous (reports mutation detected on unmutated copy)")
            end
            println("  control: not detected")
            # Verify may touch the temp tree (probes, configs); reset before mutating.
            cp(MUTATION_ROOT, tmp; force = true)
            path = joinpath(tmp, String(rel_path))
            isfile(path) || error("$name: missing source in temp copy $rel_path")
            write(path, patched)
            cmp_proc = run(ignorestatus(`cmp -s $real_path $path`))
            cmp_proc.exitcode == 0 && error("$name: cmp shows temp copy unchanged after mutation")
            load_cmd = _julia_project_cmd(tmp, "-e", "using AgentRuleLint")
            load_proc = run(ignorestatus(setenv(load_cmd; dir = tmp)))
            load_proc.exitcode != 0 && error("$name: using AgentRuleLint failed after mutation")
            if !verify(tmp)
                throw(MutationSurvived("$name: fail-closed check still passed after mutation"))
            end
            println("  mutated: detected")
            println("PASS: ", name)
        finally
            rm(tmp; recursive = true, force = true)
        end
        assert_real_src_clean()
        return nothing
    catch err
        if err isa MutationSurvived
            println(stderr, err.msg)
            exit(1)
        end
        showerror(stderr, err)
        println(stderr)
        exit(3)
    end
end
