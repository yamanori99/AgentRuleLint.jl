# Detector helper for unused-expect (path, line) mutation.
# exit 0 = same-line collision still reports unused expect; exit 42 = mutation leaked.
using AgentRuleLint

const ROOT = normpath(joinpath(@__DIR__, ".."))
const NEAR_MISS_REL = "test/corpus/expect_text_near_miss.toml"
const STANDALONE_REL = "test/corpus/expect_text_standalone.toml"
const COLLISION_PATHS = [STANDALONE_REL, NEAR_MISS_REL]

res = AgentRuleLint.check(ROOT; paths = COLLISION_PATHS)
got_n = count(
    d ->
    d.rule_id == "expect-audit" &&
        d.path == NEAR_MISS_REL &&
        d.message == "unused expect" &&
        d.anchor_line == 1,
    res.violations,
)
exit(got_n == 1 ? 0 : 42)
