@testset "expect-audit fixtures" begin
    res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus")])
    blank = any(
        d -> d.path == "test/corpus/expect_blank_line.jl" &&
            d.rule_id == "expect-audit" &&
            occursin("blank line", d.message),
        res.violations,
    )
    @test blank
    block = any(
        d -> d.path == "test/corpus/block_expect.jl" && d.rule_id == "expect-audit",
        res.violations,
    )
    @test block
    trail = any(
        d -> d.path == "test/corpus/trailing_expect.jl" &&
            d.rule_id == "expect-audit" &&
            occursin("trailing inline", d.message),
        res.violations,
    )
    @test trail
end