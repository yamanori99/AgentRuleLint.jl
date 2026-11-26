# Child worker: overlapping `check` on distinct policies (see test_check_reentrant.jl).
if length(ARGS) < 4
    error(
        "usage: check_reentrant_spawn_worker.jl <n_paths> <path_rel>... <check_root>...",
    )
end

const N_PATHS = parse(Int, ARGS[1])
length(ARGS) >= N_PATHS + 2 ||
    error("expected at least two check roots after $N_PATHS corpus path(s)")
const CORPUS_PATHS = ARGS[2:(1 + N_PATHS)]
const CHECK_ROOTS = ARGS[(2 + N_PATHS):end]
length(CHECK_ROOTS) >= 2 ||
    error("need at least two check roots for concurrent policy overlap, got $(CHECK_ROOTS)")

using AgentRuleLint

if Threads.nthreads() < 2
    error(
        "reentrant spawn worker requires at least 2 Julia threads (got $(Threads.nthreads())); " *
            "re-run with --threads>=2",
    )
end

const TASK_COUNT = max(4 * Threads.nthreads(), 16)
const BASELINES = Dict{String, AgentRuleLint.CheckResult}(
    root => AgentRuleLint.check(root; paths = CORPUS_PATHS) for root in CHECK_ROOTS
)

wall = @elapsed begin
    tasks = Vector{Task}(undef, TASK_COUNT)
    task_roots = Vector{String}(undef, TASK_COUNT)
    for i in 1:TASK_COUNT
        root = CHECK_ROOTS[mod1(i, length(CHECK_ROOTS))]
        task_roots[i] = root
        tasks[i] = Threads.@spawn AgentRuleLint.check(root; paths = CORPUS_PATHS)
    end
    for i in 1:TASK_COUNT
        got = fetch(tasks[i])
        root = task_roots[i]
        want = BASELINES[root]
        got == want ||
            error(
            "spawned check on $(root) differs from sequential baseline " *
                "(reentrancy / shared state bug)",
        )
    end
end

println(
    "check_reentrant_spawn_worker: wall=$(round(wall; digits = 3))s ",
    "tasks=$(TASK_COUNT) threads=$(Threads.nthreads()) ",
    "roots=$(length(CHECK_ROOTS)) paths=$(length(CORPUS_PATHS))",
)
exit(0)
