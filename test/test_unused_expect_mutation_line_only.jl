# Detector helper for unused-expect (path, line) mutation.
# exit 0 = same-line collision still reports unused expect; exit 42 = mutation leaked.
using AgentRuleLint

const ROOT = normpath(joinpath(@__DIR__, ".."))
const NEAR_MISS_REL = joinpath("test", "corpus", "expect_text_near_miss.toml")
const STANDALONE_REL = joinpath("test", "corpus", "expect_text_standalone.toml")
const COLLISION_PATHS = [STANDALONE_REL, NEAR_MISS_REL]

function expect_lines_in_fixture(root::AbstractString, rel::AbstractString)
    bytes = read(joinpath(root, rel))
    src = AgentRuleLint.normalize_source(String(bytes))
    return AgentRuleLint.extract_expect_lines_text(src)
end

expected_n = length(expect_lines_in_fixture(ROOT, NEAR_MISS_REL))
res = AgentRuleLint.check(ROOT; paths = COLLISION_PATHS)
got_n = count(
    d ->
    d.rule_id == "expect-audit" &&
        d.path == NEAR_MISS_REL &&
        d.message == "unused expect",
    res.violations,
)
exit(got_n == expected_n ? 0 : 42)
