# Built-in ceiling-ratchet: RuleDef and explain text.
# Ceiling load / enforce helpers live in `src/ratchet.jl`.

const _CEILING_RATCHET_EXPLAIN_DETAIL = """
Group: integrity. Level: forbid (no inline expects).

Compares live violation and expect counts against `.agentrulelint/ceilings.toml`.
Full-repository `check` reads the working-tree ceilings only (implicit ceiling 0 when a
`(rule, path)` pair has no entry). `check --diff <base>` also compares against the base
ref: removing the file, raising a stored ceiling, or adding a new positive ceiling without
a matching base entry fails closed.

`ratchet --write` merges scoped counts into the existing ceilings file; a full-repository
write replaces the file from the scanned tree.
"""

function ceiling_ratchet_explain_extra()
    return Dict{Symbol, String}(:detail => strip(_CEILING_RATCHET_EXPLAIN_DETAIL))
end

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
