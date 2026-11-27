@testset "mutation harness shard" begin
    include(joinpath(@__DIR__, "mutation", "run_all_lib.jl"))

    mutation_dir = joinpath(@__DIR__, "mutation")

    function mutation_harness_paths_from_dir(dir::AbstractString)
        skip = Set(["mutation_lib.jl", "run_all.jl", "run_all_lib.jl"])
        paths = String[]
        for name in readdir(dir)
            endswith(name, ".jl") || continue
            name in skip && continue
            push!(paths, joinpath(dir, name))
        end
        return sort(paths)
    end

    full = mutation_harness_paths_from_dir(mutation_dir)
    @test !isempty(full)

    for n in 1:4
        collected = String[]
        for i in 1:n
            append!(collected, select_mutation_shard(full, i, n))
        end
        @test sort(collected) == sort(full)
        @test length(unique(collected)) == length(full)
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