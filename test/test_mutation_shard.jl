@testset "mutation harness shard" begin
    include(joinpath(@__DIR__, "mutation", "run_all_lib.jl"))

    function assert_mutation_partition(scripts::Vector{String}, n::Int)
        collected = String[]
        sizes = Int[]
        for i in 1:n
            shard = select_mutation_shard(scripts, i, n)
            push!(sizes, length(shard))
            append!(collected, shard)
        end
        @test sort(collected) == sort(scripts)
        @test length(unique(collected)) == length(scripts)
        @test isempty(setdiff(scripts, collected))
        @test isempty(setdiff(collected, scripts))
        if !isempty(sizes)
            @test maximum(sizes) - minimum(sizes) <= 1
        end
        for i in 1:n
            shard = select_mutation_shard(scripts, i, n)
            prev_idx = 0
            for s in shard
                idx = findfirst(==(s), scripts)
                @test idx !== nothing
                @test idx > prev_idx
                prev_idx = idx
            end
        end
    end

    for m in 0:10
        scripts = ["h$(k).jl" for k in 1:m]
        for n in 1:4
            assert_mutation_partition(scripts, n)
        end
    end

    full = discover_mutation_scripts()
    @test !isempty(full)
    for n in 1:4
        assert_mutation_partition(full, n)
    end

    withenv("AGENTRULELINT_MUTATION_SHARD" => nothing) do
        @test parse_mutation_shard() === nothing
        @test apply_mutation_shard(full) == full
    end

    withenv("AGENTRULELINT_MUTATION_SHARD" => "") do
        @test parse_mutation_shard() === nothing
        @test apply_mutation_shard(full) == full
    end

    for bad in ("nope", "1/", "/3", "1-3", "0/3", "4/3", "1/0", "1/3/5")
        withenv("AGENTRULELINT_MUTATION_SHARD" => bad) do
            @test_throws ArgumentError parse_mutation_shard()
        end
    end
end
