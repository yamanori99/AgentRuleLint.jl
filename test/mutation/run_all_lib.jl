# Shared mutation runner (included from run_all.jl and tests).

const _MUTATION_RUN_DIR = @__DIR__
const _MUTATION_REPO_ROOT = normpath(joinpath(_MUTATION_RUN_DIR, "..", ".."))

include(joinpath(_MUTATION_RUN_DIR, "mutation_lib.jl"))

function discover_mutation_scripts(dir::AbstractString = _MUTATION_RUN_DIR)
    skip = Set(["mutation_lib.jl", "run_all.jl", "run_all_lib.jl"])
    scripts = String[]
    for name in readdir(dir)
        endswith(name, ".jl") || continue
        name in skip && continue
        push!(scripts, joinpath(dir, name))
    end
    return sort(scripts)
end

function parse_mutation_jobs()
    raw = get(ENV, "AGENTRULELINT_MUTATION_JOBS", "")
    if isempty(strip(raw))
        return max(1, min(3, Sys.CPU_THREADS ÷ 2))
    end
    m = match(r"^(\d+)$", strip(raw))
    m === nothing && throw(
        ArgumentError(
            "AGENTRULELINT_MUTATION_JOBS must be a positive integer, got $(repr(raw))",
        ),
    )
    n = parse(Int, m.captures[1]::SubString)
    n <= 0 &&
        throw(ArgumentError("AGENTRULELINT_MUTATION_JOBS must be positive, got $n"))
    return n
end

function _mutation_cmd(script::AbstractString)
    return ignorestatus(
        setenv(
            `$(Base.julia_cmd()) --startup-file=no --project=$(_MUTATION_REPO_ROOT) $(script)`;
            dir = _MUTATION_REPO_ROOT,
        ),
    )
end

function run_one_mutation_captured(script::AbstractString)
    name = basename(script)
    stdout_path = tempname()
    stderr_path = tempname()
    cmd = _mutation_cmd(script)
    t0 = time()
    try
        proc = run(pipeline(cmd, stdout = stdout_path, stderr = stderr_path))
        elapsed = time() - t0
        stdout = isfile(stdout_path) ? read(stdout_path, String) : ""
        stderr = isfile(stderr_path) ? read(stderr_path, String) : ""
        sig = proc.termsignal
        code = proc.exitcode
        result = if sig != 0
            :crash
        elseif code == 0
            :pass
        elseif code == 1
            :fail
        else
            :crash
        end
        return (; name, result, code, termsignal = sig, elapsed, stdout, stderr)
    finally
        rm(stdout_path, force = true)
        rm(stderr_path, force = true)
    end
end

function run_mutation_harnesses(scripts::Vector{String}; jobs::Int = parse_mutation_jobs())
    isempty(scripts) && return NamedTuple[]
    n = length(scripts)
    jobs = max(1, jobs)
    results = Vector{Any}(undef, n)
    slot = Threads.Atomic{Int}(1)
    pool = min(jobs, n)

    worker = function ()
        while true
            i = Threads.atomic_add!(slot, 1)
            i > n && break
            results[i] = run_one_mutation_captured(scripts[i])
        end
        return nothing
    end

    @sync for _ in 1:pool
        @async worker()
    end

    return [results[i]::NamedTuple for i in eachindex(scripts)]
end

function print_mutation_report(results)
    failed = 0
    for r in results
        r.stdout != "" && print(r.stdout)
        r.stderr != "" && print(stderr, r.stderr)
        label = r.result === :pass ? "PASS" : (r.result === :fail ? "FAIL" : "CRASH")
        elapsed = round(r.elapsed; digits = 1)
        status =
            r.termsignal == 0 ? "(exit $(r.code))" :
            "(exit $(r.code), signal $(r.termsignal))"
        line = lpad(string(r.name), 48) * "  " * label * "  " * string(elapsed) * "s  " * status * "\n"
        print(line)
        r.result !== :pass && (failed += 1)
    end
    return failed
end

"""Print dirty `src/` status after mutation harnesses; return whether the tree is dirty."""
function _dirty_src_after_mutations(root::AbstractString)
    status = read(`git -C $(root) status --porcelain -- src`, String)
    if isempty(strip(status))
        return false
    end
    println(stderr, "real src/ is dirty after mutation harness:\n", status)
    return true
end

function mutation_run_all_main(dir::AbstractString = _MUTATION_RUN_DIR)
    scripts = discover_mutation_scripts(dir)
    if isempty(scripts)
        println(stderr, "mutation run_all: zero mutation files found under $dir")
        return 1
    end

    jobs = parse_mutation_jobs()
    println("mutation run_all: $(length(scripts)) file(s) (jobs=$jobs)")
    wall0 = time()
    results = run_mutation_harnesses(scripts; jobs = jobs)

    failed = print_mutation_report(results)

    _dirty_src_after_mutations(_MUTATION_REPO_ROOT) && return 1

    wall = round(time() - wall0; digits = 1)
    sum_elapsed = round(sum(r.elapsed for r in results); digits = 1)
    println(
        "mutation run_all: done — $(length(results) - failed)/$(length(results)) passed, wall≈$(wall)s (sum of scripts $(sum_elapsed)s)",
    )
    return failed == 0 ? 0 : 1
end
