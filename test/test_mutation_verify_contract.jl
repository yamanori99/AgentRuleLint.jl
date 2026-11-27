@testset "mutation verify subprocess exit contract" begin
    include(joinpath(@__DIR__, "mutation", "mutation_lib.jl"))

    @test !mutation_verify_script(MUTATION_ROOT, "exit(0)"; dir = MUTATION_ROOT)
    @test mutation_verify_script(
        MUTATION_ROOT,
        "exit($(_MUTATION_VERIFY_DETECTED_EXIT))",
        dir = MUTATION_ROOT,
    )
    @test_throws MutationVerifyCrashed mutation_verify_script(
        MUTATION_ROOT,
        "exit(1)",
        dir = MUTATION_ROOT,
    )
    @test_throws MutationVerifyCrashed redirect_stderr(devnull) do
        mutation_verify_script(
            MUTATION_ROOT,
            "this is not valid Julia syntax",
            dir = MUTATION_ROOT,
        )
    end
end
