# Detector helper for unused-expect (path, line) mutation.
# exit 0 = same-line collision still reports unused expect; exit 42 = mutation leaked.
using AgentRuleLint

const ROOT = normpath(joinpath(@__DIR__, ".."))
const FIXTURE_DIR = joinpath("test", "corpus", "unused_expect_same_line")
const UNUSED_REL = joinpath(FIXTURE_DIR, "line_collision_unused.toml")

function expect_lines_in_fixture(root::AbstractString, rel::AbstractString)
    bytes = read(joinpath(root, rel))
    src = AgentRuleLint.normalize_source(String(bytes))
    return AgentRuleLint.extract_expect_lines_text(src)
end

expected_n = length(expect_lines_in_fixture(ROOT, UNUSED_REL))
res = AgentRuleLint.check(ROOT; paths = [FIXTURE_DIR])
got_n = count(
    d ->
    d.rule_id == "expect-audit" &&
        d.path == UNUSED_REL &&
        d.message == "unused expect",
    res.violations,
)
exit(got_n == expected_n ? 0 : 42)
