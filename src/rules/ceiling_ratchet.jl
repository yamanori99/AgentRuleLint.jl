# Built-in ceiling-ratchet: RuleDef.
# Ceiling load / enforce helpers live in `src/ratchet.jl`.

const CEILING_RATCHET_RULE_DEF = RuleDef(
    CEILING_RATCHET_RULE,
    :agentrulelint,
    :forbid,
    "Keep violation and expect ceilings monotonic (down only).",
    "Raise ceilings or leave stale slack after counts decrease.",
    Dict{Symbol, String}(),
    "ceiling_ratchet.jl",
    "test_ceiling_ratchet.jl",
    ("test/test_ceiling_ratchet.jl",),
)
