using AgentRuleLint
using ParallelTestRunner
using Test

import ParallelTestRunner: filter_tests!, parse_args, runtests

const TEST_DIR = @__DIR__
const ROOT = dirname(TEST_DIR)
include(joinpath(TEST_DIR, "failure_digest.jl"))
include(joinpath(TEST_DIR, "parallel_testsuite_config.jl"))

const _FAILURE_DIGEST_TS = Ref{Union{Nothing, Test.DefaultTestSet}}(nothing)

function _arl_ptr_with_testset_impl(f, testset)
    Test.@with_testset testset f()
    return nothing
end

if !isdefined(ParallelTestRunner, :__ARL_WITH_TESTSET_HOOKED)
    ParallelTestRunner.eval(
        quote
            global function with_testset(f, testset)
                if testset isa Test.DefaultTestSet && testset.description == "Overall"
                    Main._FAILURE_DIGEST_TS[] = testset
                end
                return Main._arl_ptr_with_testset_impl(f, testset)
            end
            __ARL_WITH_TESTSET_HOOKED = true
        end,
    )
end

function build_testsuite()
    tests = Dict{String, Expr}()
    for fname in readdir(TEST_DIR)
        startswith(fname, "test_") && endswith(fname, ".jl") || continue
        name = fname[1:(end - 3)]
        name in _MUTATION_HELPER_ONLY_TESTS && continue
        path = joinpath(TEST_DIR, fname)
        tests[name] = :(include($path))
    end
    return tests
end

const init_code = quote
    const ROOT = $(ROOT)
    const CORPUS = $(joinpath(ROOT, "test", "corpus"))
    include($(joinpath(TEST_DIR, "failure_digest.jl")))
    include($(joinpath(TEST_DIR, "golden_test_helpers.jl")))
    include($(joinpath(TEST_DIR, "mutation_subprocess_helpers.jl")))
    using AgentRuleLint
    using Test
    using Aqua
    using JSON
end

const _SERIAL_AFTER = [
    "test_parallel_runner_digest_hook", # test/last_failures.txt
    "test_src_untouched", # git status --porcelain -- src
]

function run_agentrulelint_tests()
    testsuite = build_testsuite()
    args = parse_args(ARGS)
    # Probe-only suites (e.g. test_digest_deliberate_fail) stay out of the default run.
    if filter_tests!(testsuite, args) && isempty(args.positionals)
        for probe in _PROBE_ONLY_TESTS
            delete!(testsuite, probe)
        end
    end
    try
        runtests(
            AgentRuleLint,
            args;
            testsuite,
            init_code,
            serial = _SERIAL_AFTER,
            serial_position = :after,
        )
    catch err
        err isa InterruptException && rethrow()
        let ts = _FAILURE_DIGEST_TS[]
            ts isa Test.DefaultTestSet && emit_failure_digest(ts)
        end
        rethrow()
    end
    let ts = _FAILURE_DIGEST_TS[]
        ts isa Test.DefaultTestSet && emit_failure_digest(ts)
    end
    return nothing
end

run_agentrulelint_tests()