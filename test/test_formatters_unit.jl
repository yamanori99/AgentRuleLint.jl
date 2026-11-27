@testset "formatters" begin
    cs = AgentRuleLint.ConfigSource()
    d = AgentRuleLint.Violation(
        "project/test",
        :project,
        :deny,
        "test/corpus/split_string.jl",
        AgentRuleLint.Span(1, 1, 1, 10),
        1,
        "v1:abc",
        :none,
        false,
        "forbidden literal matched",
        "i",
        "d",
    )
    res = AgentRuleLint.CheckResult([d], true, 1, cs, :human, 20, 0, 1)
    io = IOContext(IOBuffer(), :color => false)
    human = AgentRuleLint.format_human(res; root = ROOT, io = io)
    @test occursin("[Project]", human)
    @test occursin("└ @ Project", human)
    @test occursin("RULE", AgentRuleLint.format_agent(res; root = ROOT))
    @test occursin("\"type\":\"header\"", replace(AgentRuleLint.format_json(res), " " => ""))
end