# Entry point for standalone mutation harnesses under `test/mutation/`.
# Discover `*.jl` via glob (except `mutation_lib.jl` / this file); run each in a
# fresh Julia process. Exit non-zero if any mutation survives, a harness crashes,
# zero files are found, or real `src/` is dirty afterwards.

using Printf

const MUTATION_DIR = @__DIR__
const REPO_ROOT = normpath(joinpath(MUTATION_DIR, "..", ".."))

include(joinpath(MUTATION_DIR, "mutation_lib.jl"))

function discover_mutation_scripts(dir::AbstractString = MUTATION_DIR)
    skip = Set(["mutation_lib.jl", "run_all.jl"])
    scripts = String[]
    for name in readdir(dir)
        endswith(name, ".jl") || continue
        name in skip && continue
        push!(scripts, joinpath(dir, name))
    end
    return sort(scripts)
end

function run_one_mutation(script::AbstractString)
    name = basename(script)
    # Same interpreter as this process (CI: setup-julia 1.13; local: `julia +1.13 …`).
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(REPO_ROOT) $(script)`
    t0 = time()
    proc = run(ignorestatus(setenv(cmd; dir = REPO_ROOT)))
    elapsed = time() - t0
    code = proc.exitcode
    if code == 0
        return (; name, result = :pass, code, elapsed)
    elseif code == 1
        # MutationSurvived / verify failed: mutation was not killed.
        return (; name, result = :fail, code, elapsed)
    else
        # Harness crash (exit 3 from mutation_lib, or unexpected codes).
        return (; name, result = :crash, code, elapsed)
    end
end

function main()
    scripts = discover_mutation_scripts()
    if isempty(scripts)
        println(stderr, "mutation run_all: zero mutation files found under $MUTATION_DIR")
        return 1
    end

    println("mutation run_all: $(length(scripts)) file(s) under test/mutation/")
    failed = 0
    results = NamedTuple[]
    for script in scripts
        r = run_one_mutation(script)
        push!(results, r)
        label = r.result === :pass ? "PASS" : (r.result === :fail ? "FAIL" : "CRASH")
        @printf("%-48s  %s  %.1fs  (exit %d)\n", r.name, label, r.elapsed, r.code)
        if r.result !== :pass
            failed += 1
        end
    end

    try
        assert_real_src_clean(REPO_ROOT)
    catch err
        println(stderr, err)
        return 1
    end

    total = round(sum(r.elapsed for r in results); digits = 1)
    println(
        "mutation run_all: done — $(length(results) - failed)/$(length(results)) passed, wall≈$(total)s (sum of scripts)",
    )
    return failed == 0 ? 0 : 1
end

exit(main())
