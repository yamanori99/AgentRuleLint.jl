@testset "Pkg.test shard" begin
    include(joinpath(@__DIR__, "mutation", "run_all_lib.jl"))
    include(joinpath(@__DIR__, "parallel_testsuite_config.jl"))

    function discover_pkg_test_names()
        names = String[]
        test_dir = @__DIR__
        for fname in readdir(test_dir)
            startswith(fname, "test_") && endswith(fname, ".jl") || continue
            name = fname[1:(end - 3)]
            name in _MUTATION_HELPER_ONLY_TESTS && continue
            push!(names, name)
        end
        return sort!(names)
    end

    function assert_test_partition(names::Vector{String}, n::Int)
        collected = String[]
        sizes = Int[]
        for i in 1:n
            shard = select_mutation_shard(names, i, n)
            push!(sizes, length(shard))
            append!(collected, shard)
        end
        @test sort(collected) == names
        @test length(unique(collected)) == length(names)
        @test isempty(setdiff(names, collected))
        @test isempty(setdiff(collected, names))
        if !isempty(sizes)
            @test maximum(sizes) - minimum(sizes) <= 1
        end
    end

    full = discover_pkg_test_names()
    @test !isempty(full)
    for n in 1:4
        assert_test_partition(full, n)
    end

    function parse_test_shard()
        raw = get(ENV, "AGENTRULELINT_TEST_SHARD", "")
        return withenv("AGENTRULELINT_MUTATION_SHARD" => raw) do
            parse_mutation_shard()
        end
    end

    withenv("AGENTRULELINT_TEST_SHARD" => nothing) do
        @test parse_test_shard() === nothing
    end

    withenv("AGENTRULELINT_TEST_SHARD" => "2/3") do
        @test parse_test_shard() == (2, 3)
        sel = select_mutation_shard(full, 2, 3)
        n = 3
        lo, hi = length(full) ÷ n, length(full) ÷ n + 1
        @test length(sel) in (lo, hi)
        for other in 1:n
            other == 2 && continue
            @test isempty(intersect(sel, select_mutation_shard(full, other, n)))
        end
    end

    for bad in ("nope", "1/", "/3", "0/3", "4/3")
        withenv("AGENTRULELINT_TEST_SHARD" => bad) do
            @test_throws ArgumentError parse_test_shard()
        end
    end
end
