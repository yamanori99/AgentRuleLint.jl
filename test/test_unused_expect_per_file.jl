const _UNUSED_EXPECT_FIXTURE_DIR = joinpath("test", "corpus", "unused_expect_same_line")
const _UNUSED_EXPECT_UNUSED_REL =
    joinpath(_UNUSED_EXPECT_FIXTURE_DIR, "line_collision_unused.toml")
const _UNUSED_EXPECT_USED_REL =
    joinpath(_UNUSED_EXPECT_FIXTURE_DIR, "line_collision_used.toml")

@testset "unused expect keyed by (path, line)" begin

    function expect_lines_in_fixture(rel::AbstractString)
        root = ROOT
        path = joinpath(root, rel)
        bytes = read(path)
        src = AgentRuleLint.normalize_source(String(bytes))
        return AgentRuleLint.extract_expect_lines_text(src)
    end

    unused_expects = expect_lines_in_fixture(_UNUSED_EXPECT_UNUSED_REL)
    @test !isempty(unused_expects)
    @test all(ex -> ex.line == 1, unused_expects)
    used_expects = expect_lines_in_fixture(_UNUSED_EXPECT_USED_REL)
    @test !isempty(used_expects)
    @test all(ex -> ex.line == 1, used_expects)

    res = AgentRuleLint.check(ROOT; paths = [_UNUSED_EXPECT_FIXTURE_DIR])
    unused_diags = filter(
        d ->
        d.rule_id == "expect-audit" &&
            d.path == _UNUSED_EXPECT_UNUSED_REL &&
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
            d.path == _UNUSED_EXPECT_USED_REL &&
            d.message == "unused expect",
        res.violations,
    )
end
