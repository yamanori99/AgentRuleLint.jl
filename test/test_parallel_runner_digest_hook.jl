@testset "ParallelTestRunner failure digest hook" begin
    @testset "deliberate failing file writes digest" begin
        julia = joinpath(Sys.BINDIR, Base.julia_exename())
        digest_path = joinpath(ROOT, "test", "last_failures.txt")
        cmd = setenv(
            `$julia --startup-file=no --project=$ROOT -e 'using Pkg; Pkg.test(test_args=["test_digest_deliberate_fail", "--jobs=1"])'`,
            "JULIA_LOAD_PATH" => "@:@stdlib",
        )
        @test !success(run(ignorestatus(cmd)))
        @test isfile(digest_path)
        text = read(digest_path, String)
        @test startswith(text, FAILURE_DIGEST_MARKER)
        @test occursin("FAIL", text)
        @test occursin("test_digest_deliberate_fail", text)
        @test occursin("test/test_digest_deliberate_fail.jl:", text)
    end
end