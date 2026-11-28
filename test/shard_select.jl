# Pkg.test shard selection (included from runtests.jl and tests; not auto-discovered).

const _TEST_SHARD_LIB_DIR = @__DIR__
include(joinpath(_TEST_SHARD_LIB_DIR, "mutation", "run_all_lib.jl"))
include(joinpath(_TEST_SHARD_LIB_DIR, "parallel_testsuite_config.jl"))

const AGENTRULELINT_TEST_SHARD_ENV = "AGENTRULELINT_TEST_SHARD"

function discover_pkg_test_names(test_dir::AbstractString = _TEST_SHARD_LIB_DIR)
    names = String[]
    for fname in readdir(test_dir)
        startswith(fname, "test_") && endswith(fname, ".jl") || continue
        name = fname[1:(end - 3)]
        name in _MUTATION_HELPER_ONLY_TESTS && continue
        name in _PROBE_ONLY_TESTS && continue
        push!(names, name)
    end
    return sort(names)
end

function parse_test_shard()
    return withenv("AGENTRULELINT_MUTATION_SHARD" => get(ENV, AGENTRULELINT_TEST_SHARD_ENV, "")) do
        return parse_mutation_shard()
    end
end

function apply_test_shard(names::AbstractVector{String})
    sorted = sort(collect(names))
    shard = parse_test_shard()
    shard === nothing && return sorted
    i, n = shard
    return select_mutation_shard(sorted, i, n)
end

function apply_test_shard!(testsuite::Dict{String, Expr})
    shard = parse_test_shard()
    shard === nothing && return nothing
    keep = Set(apply_test_shard(collect(keys(testsuite))))
    for k in collect(keys(testsuite))
        k in keep || delete!(testsuite, k)
    end
    i, n = shard
    println(
        "Pkg.test shard $i/$n; $(length(testsuite)) test file(s): ",
        join(sort(collect(keys(testsuite))), ", "),
    )
    return nothing
end
