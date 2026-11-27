# Harness self-check: a child killed by a signal must be CRASH, not PASS (exitcode can be 0).

include("run_all_lib.jl")

mktempdir() do tmp
    src = joinpath(tmp, "kill_self.jl")
    write(src, "run(Cmd([\"kill\", \"-KILL\", string(getpid())]))\n")
    r = run_one_mutation_captured(src)
    r.result === :crash ||
        error("signaled harness child expected :crash, got $(r.result) (exit $(r.code), signal $(r.termsignal))")
    r.termsignal != 0 || error("signaled harness child expected nonzero termsignal")
end

println("PASS: harness signal self-check")
