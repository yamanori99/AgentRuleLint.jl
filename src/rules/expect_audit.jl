# Built-in expect-audit: RuleDef and explain text.
# Diagnostic runners live in `src/expect.jl` (shared expect parsing / suppression).

const EXPECT_AUDIT_ID = "expect-audit"

const EXPECT_AUDIT_EXPECT_ANCHOR = """
First non-blank code line after contiguous `# agentrulelint-expect:` lines that matches the target syntax kind for the referenced rule (e.g. `try`, `@eval`, `@test*`).
"""

const EXPECT_AUDIT_EXAMPLE = """
# agentrulelint-expect: expect-audit reason="documented suppression"
@eval :ok
"""

const EXPECT_AUDIT_SYNTAX = """
Syntax: `# agentrulelint-expect: <rule-id> reason="..."` (ASCII, standalone line only; non-empty reason).
"""

const EXPECT_AUDIT_SUPPRESSION = """
Suppresses only violations whose anchor_line matches that line.
Expects are forbidden above `catch`, inside `# runic: off` regions, inside multiline
call arguments, and with blank lines before the anchor. Forbidden placements do not
suppress violations. Multiline-call placement uses the same forbid level as other
expect-audit integrity findings.
"""

function expect_audit_explain_extra()
    return Dict{Symbol, String}(
        :expect_anchor => strip(EXPECT_AUDIT_EXPECT_ANCHOR),
        :syntax => strip(EXPECT_AUDIT_SYNTAX),
        :suppression => strip(EXPECT_AUDIT_SUPPRESSION),
        :example => strip(EXPECT_AUDIT_EXAMPLE),
    )
end

const EXPECT_AUDIT_RULE_DEF = RuleDef(
    EXPECT_AUDIT_ID,
    :agentrulelint,
    :forbid,
    "Keep suppression comments auditable and fail-closed.",
    "Use inline or block comment expects to hide violations.",
    Dict{Symbol, String}(),
    "expect_audit.jl",
    "test_expect_audit.jl",
    ("test/corpus/expect_blank_line.jl",),
)
