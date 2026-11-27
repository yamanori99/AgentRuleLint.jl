@testset "corpus golden per file" begin
    expect_hits = Dict(
        "split_string.jl" => true,
        "split_star.jl" => true,
        "join_three.jl" => true,
        "expect_standalone.jl" => false,
        "utf8_multibyte.jl" => false,
        "bom_utf8.jl" => false,
        "reduce_nonconcat.jl" => false,
        "reduce_star.jl" => true,
    )
    for (file, want_hit) in expect_hits
        res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", file)])
        hits = any(
            d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            res.violations,
        )
        @test hits == want_hit
    end
end