const _UNUSED_EXPECT_NEAR_MISS_REL = "test/corpus/expect_text_near_miss.toml"
const _UNUSED_EXPECT_STANDALONE_REL = "test/corpus/expect_text_standalone.toml"
const _UNUSED_EXPECT_COLLISION_PATHS = [
    _UNUSED_EXPECT_STANDALONE_REL,
    _UNUSED_EXPECT_NEAR_MISS_REL,
]

@testset "unused expect keyed by (path, line)" begin
    res = AgentRuleLint.check(ROOT; paths = _UNUSED_EXPECT_COLLISION_PATHS)
    unused_diags = filter(
        d ->
        d.rule_id == "expect-audit" &&
            d.path == _UNUSED_EXPECT_NEAR_MISS_REL &&
            d.message == "unused expect",
        res.violations,
    )
    @test length(unused_diags) == 1
    @test unused_diags[1].anchor_line == 1
    @test !unused_diags[1].suppressed
    @test !any(
        d ->
        d.rule_id == "expect-audit" &&
            d.path == _UNUSED_EXPECT_STANDALONE_REL &&
            d.message == "unused expect",
        res.violations,
    )
end
