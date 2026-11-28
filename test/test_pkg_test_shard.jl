@testset "Pkg.test shard" begin
    include("shard_select.jl")

    function assert_pkg_test_partition(names::Vector{String}, n::Int)
        collected = String[]
        sizes = Int[]
        for i in 1:n
            shard = select_mutation_shard(names, i, n)
            push!(sizes, length(shard))
            append!(collected, shard)
        end
        @test sort(collected) == sort(names)
        @test length(unique(collected)) == length(names)
        @test isempty(setdiff(names, collected))
        @test isempty(setdiff(collected, names))
        if !isempty(sizes)
            @test maximum(sizes) - minimum(sizes) <= 1
        end
        for i in 1:n
            shard = select_mutation_shard(names, i, n)
            prev_idx = 0
            for s in shard
                idx = findfirst(==(s), names)
                @test idx !== nothing
                @test idx > prev_idx
                prev_idx = idx
            end
        end
    end

    full = discover_pkg_test_names()
    @test !isempty(full)
    @test full == sort(full)
    for n in 1:4
        assert_pkg_test_partition(full, n)
    end

    withenv("AGENTRULELINT_TEST_SHARD" => nothing) do
        @test parse_test_shard() === nothing
        @test apply_test_shard(full) == full
    end

    withenv("AGENTRULELINT_TEST_SHARD" => "") do
        @test parse_test_shard() === nothing
        @test apply_test_shard(full) == full
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

    for bad in ("nope", "1/", "/3", "1-3", "0/3", "4/3", "1/0", "1/3/5")
        withenv("AGENTRULELINT_TEST_SHARD" => bad) do
            @test_throws ArgumentError parse_test_shard()
        end
    end

    withenv("AGENTRULELINT_TEST_SHARD" => "1/3") do
        shard = apply_test_shard(full)
        @test shard == select_mutation_shard(full, 1, 3)
        empty_suite = Dict{String, Expr}()
        apply_test_shard!(empty_suite)
        @test isempty(empty_suite)
    end
end
