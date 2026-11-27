const _UNUSED_EXPECT_NEAR_MISS_REL = joinpath("test", "corpus", "expect_text_near_miss.toml")
const _UNUSED_EXPECT_STANDALONE_REL = joinpath("test", "corpus", "expect_text_standalone.toml")
const _UNUSED_EXPECT_COLLISION_PATHS = [
    _UNUSED_EXPECT_STANDALONE_REL,
    _UNUSED_EXPECT_NEAR_MISS_REL,
]

@testset "unused expect keyed by (path, line)" begin

    function expect_lines_in_fixture(rel::AbstractString)
        root = ROOT
        path = joinpath(root, rel)
        bytes = read(path)
        src = AgentRuleLint.normalize_source(String(bytes))
        return AgentRuleLint.extract_expect_lines_text(src)
    end

    unused_expects = expect_lines_in_fixture(_UNUSED_EXPECT_NEAR_MISS_REL)
    @test !isempty(unused_expects)
    @test all(ex -> ex.line == 1, unused_expects)
    used_expects = expect_lines_in_fixture(_UNUSED_EXPECT_STANDALONE_REL)
    @test !isempty(used_expects)
    @test all(ex -> ex.line == 1, used_expects)

    res = AgentRuleLint.check(ROOT; paths = _UNUSED_EXPECT_COLLISION_PATHS)
    unused_diags = filter(
        d ->
        d.rule_id == "expect-audit" &&
            d.path == _UNUSED_EXPECT_NEAR_MISS_REL &&
            d.message == "unused expect",
        res.violations,
    )
    @test length(unused_diags) == length(unused_expects)
    for (ex, d) in zip(unused_expects, unused_diags)
        @test d.anchor_line == ex.line
        @test !d.suppressed
    end
    @test !any(
        d ->
        d.rule_id == "expect-audit" &&
            d.path == _UNUSED_EXPECT_STANDALONE_REL &&
            d.message == "unused expect",
        res.violations,
    )
end
