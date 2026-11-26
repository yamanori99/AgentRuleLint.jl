using AgentRuleLint
using Test

"""Intent and `do_not` bodies from `format_explain_rule` output (no config overrides)."""
function explain_intent_do_not(text::AbstractString)
    intent_key = "intent:\n"
    do_not_key = "\ndo_not:\n"
    i0 = findfirst(intent_key, text)
    i0 === nothing && error("missing intent block")
    i1 = findfirst(do_not_key, text)
    i1 === nothing && error("missing do_not block")
    intent = strip(text[(Base.last(i0) + 1):(Base.first(i1) - 1)])
    rest = text[(Base.last(i1) + 1):end]
    stop_re = r"\n(?:anchor_line|syntax|suppression|intent_detail|config|detail|expect_anchor|example):"
    m = match(stop_re, rest)
    do_not = if m === nothing
        strip(rest)
    else
        stop = m.offset - 1
        strip(rest[1:stop])
    end
    return intent, do_not
end

@testset "RuleDef intent/do_not matches explain" begin
    tmp = mktempdir()
    mkpath(joinpath(tmp, "test"))
    try
        for def in AgentRuleLint.RULE_DEFS
            text = AgentRuleLint.explain_rule(def.id; root = tmp)
            got_intent, got_do_not = explain_intent_do_not(text)
            @test got_intent == def.intent
            @test got_do_not == def.do_not
        end
    finally
        rm(tmp; recursive = true, force = true)
    end
end
