@testset "report CLI" begin
    res = AgentRuleLint.check(ROOT; paths = [joinpath("test", "corpus", "split_string.jl")])
    d = first(filter(x -> x.rule_id == "project/no-internal-codename" && !x.suppressed, res.violations))
    out = AgentRuleLint.format_report(d.fingerprint, d, "secret = \"x\"\n")
    @test occursin("pattern_hash", out)
    cd(ROOT) do
        @test AgentRuleLint.cli_main(["report", d.fingerprint]) == 0
        @test AgentRuleLint.cli_main(["report", "v1:000000000000000000000000000000000000000000"]) == 2
    end
end
