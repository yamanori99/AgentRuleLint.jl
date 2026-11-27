using Test

include(joinpath(@__DIR__, "parallel_testsuite_config.jl"))

function _referenced_in_test_tree(name::String, test_dir::String, runtests_path::String)
    rel = "test/$name.jl"
    for (root, _, files) in walkdir(test_dir)
        for fname in files
            endswith(fname, ".jl") || continue
            path = joinpath(root, fname)
            path == runtests_path && continue
            text = read(path, String)
            if occursin(name, text) || occursin(rel, text)
                return true
            end
        end
    end
    return false
end

@testset "ParallelTestRunner suite exclusions" begin
    test_dir = @__DIR__
    runtests_path = joinpath(test_dir, "runtests.jl")
    runtests_text = read(runtests_path, String)

    for name in _MUTATION_HELPER_ONLY_TESTS
        @test isfile(joinpath(test_dir, "$name.jl"))
        @test _referenced_in_test_tree(name, test_dir, runtests_path)
    end

    for name in _PROBE_ONLY_TESTS
        @test isfile(joinpath(test_dir, "$name.jl"))
        @test occursin(name, runtests_text)
        @test occursin("_PROBE_ONLY_TESTS", runtests_text)
    end
end
