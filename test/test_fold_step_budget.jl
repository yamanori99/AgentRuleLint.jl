@testset "fold step budget" begin
    src = "a = \"x\" * \"y\"\nb = \"p\" * \"q\"\nc = \"r\" * \"s\"\n"
    tree = AgentRuleLint.parse_source(src)
    full = AgentRuleLint.collect_folded_string_exprs(tree, src)
    @test length(full.folds) >= 3
    @test !full.budget_exceeded
    # Budget exhaustion returns folds collected so far (not an empty vector).
    partial = AgentRuleLint.collect_folded_string_exprs(tree, src; max_steps = 15)
    @test !isempty(partial.folds)
    @test partial.budget_exceeded
    @test length(partial.folds) < length(full.folds)
end
