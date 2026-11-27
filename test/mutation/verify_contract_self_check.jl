# Harness self-check: verify exit contracts and vacuous-control detection must CRASH, not PASS.

include("mutation_lib.jl")

function _expect_verify_crash(f::Function)
    try
        f()
        error("expected verify helper to throw")
    catch err
        msg = sprint(showerror, err)
        (occursin("verify subprocess crashed", msg) || occursin("verify is vacuous", msg)) ||
            rethrow()
    end
    return nothing
end

@assert !mutation_verify_script(MUTATION_ROOT, "exit(0)"; dir = MUTATION_ROOT)
@assert mutation_verify_script(MUTATION_ROOT, "exit($(_MUTATION_VERIFY_DETECTED_EXIT))"; dir = MUTATION_ROOT)

function _expect_verify_script_crash(script::String)
    cmd = _julia_project_cmd(MUTATION_ROOT, "-e", script)
    proc = run(pipeline(ignorestatus(setenv(cmd; dir = MUTATION_ROOT)); stderr = devnull))
    code = proc.exitcode
    code == 0 && error("expected verify script crash, got exit 0")
    code == _MUTATION_VERIFY_DETECTED_EXIT && error("expected verify script crash, got detected")
    return nothing
end

_expect_verify_script_crash("this is not valid Julia syntax")
_expect_verify_script_crash("error(\"deliberate\")")
_expect_verify_script_crash("exit(1)")

# Vacuous verify: always reports detected → control run must exit 3 (harness CRASH).
vacuous_src = joinpath(@__DIR__, ".vacuous_probe.jl")
open(vacuous_src, "w") do io
    println(
        io,
        """
        include($(repr(joinpath(@__DIR__, "mutation_lib.jl"))))
        run_source_mutation(;
            name = "verify contract vacuous probe",
            rel_path = "src/diff.jl",
            needle = "function diff_path_status(scope::DiffScope, relpath::AbstractString)",
            replacement = "function diff_path_status(scope::DiffScope, relpath::AbstractString) # probe",
            verify = _ -> true,
        )
        """,
    )
end
vacuous_proc = run(
    ignorestatus(
        setenv(
            `$(Base.julia_cmd()) --startup-file=no --project=$(MUTATION_ROOT) $(vacuous_src)`;
            dir = MUTATION_ROOT,
        ),
    ),
)
rm(vacuous_src; force = true)
vacuous_proc.exitcode == 3 ||
    error("vacuous control expected exit 3, got $(vacuous_proc.exitcode)")

println("PASS: verify contract self-check")
