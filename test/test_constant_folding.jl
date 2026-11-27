@testset "constant folding" begin
    src = "s = \"a\" * \"b\"\n"
    tree = AgentRuleLint.parse_source(src)
    folds = AgentRuleLint.collect_folded_string_exprs(tree, src).folds
    vals = [f.value for f in folds]
    @test "ab" in vals
    full = only(filter(f -> f.value == "ab", folds))
    @test full.byte_start > 0
    @test full.byte_end >= full.byte_start
end
