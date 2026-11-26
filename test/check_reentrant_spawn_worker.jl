# Child worker: true multi-threaded `Threads.@spawn` check (see test_check_reentrant.jl).
if length(ARGS) < 2
    error("usage: check_reentrant_spawn_worker.jl <check_root> <parallel_count>")
end

const CHECK_ROOT = ARGS[1]
const PARALLEL_COUNT = parse(Int, ARGS[2])

using AgentRuleLint

if Threads.nthreads() < 2
    error(
        "reentrant spawn worker requires at least 2 Julia threads (got $(Threads.nthreads())); " *
            "re-run with --threads>=2",
    )
end

const CORPUS_PATHS = [joinpath("test", "corpus")]

seq = AgentRuleLint.check(CHECK_ROOT; paths = CORPUS_PATHS)

for _ in 1:PARALLEL_COUNT
    t = Threads.@spawn AgentRuleLint.check(CHECK_ROOT; paths = CORPUS_PATHS)
    got = fetch(t)
    got == seq ||
        error("spawned check result differs from sequential baseline (reentrancy / shared state bug)")
end

exit(0)
