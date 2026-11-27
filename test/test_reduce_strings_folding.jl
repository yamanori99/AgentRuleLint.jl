@testset "reduce(*, strings) folding" begin
    hit = "x = reduce(*, [\"INT\", \"ERNAL_CODENAME\"])\n"
    tree = AgentRuleLint.parse_source(hit)
    folds = AgentRuleLint.collect_folded_string_exprs(tree, hit).folds
    vals = [f.value for f in folds]
    @test "INTERNAL_CODENAME" in vals
    @test "INTINT" ∉ vals

    miss = "x = reduce(*, [\"INT\", \"FOO\"])\n"
    tree2 = AgentRuleLint.parse_source(miss)
    vals2 = [f.value for f in AgentRuleLint.collect_folded_string_exprs(tree2, miss).folds]
    @test "INTFOO" in vals2
    @test "INTINTFOO" ∉ vals2
end
