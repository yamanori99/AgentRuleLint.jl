@testset "src/ untouched by tests" begin
    status = read(`git -C $(ROOT) status --porcelain -- src`, String)
    @test isempty(strip(status))
end
