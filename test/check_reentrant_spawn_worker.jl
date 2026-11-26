# Child worker: true multi-threaded `Threads.@spawn` check (see test_check_reentrant.jl).
if length(ARGS) < 3
    error(
        "usage: check_reentrant_spawn_worker.jl <parallel_count> <paths_rel...> <check_root>...",
    )
end

const PARALLEL_COUNT = parse(Int, ARGS[1])
const CORPUS_PATHS = [ARGS[2]]
const CHECK_ROOTS = ARGS[3:end]

using AgentRuleLint

if Threads.nthreads() < 2
    error(
        "reentrant spawn worker requires at least 2 Julia threads (got $(Threads.nthreads())); " *
            "re-run with --threads>=2",
    )
end

for check_root in CHECK_ROOTS
    seq = AgentRuleLint.check(check_root; paths = CORPUS_PATHS)
    for _ in 1:PARALLEL_COUNT
        t = Threads.@spawn AgentRuleLint.check(check_root; paths = CORPUS_PATHS)
        got = fetch(t)
        got == seq ||
            error(
            "spawned check on $(check_root) differs from sequential baseline " *
                "(reentrancy / shared state bug)",
        )
    end
end

exit(0)
