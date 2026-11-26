# Detector helper for text-path blank-line eligibility mutation.
# exit 0 = blank-line expects still do not suppress; exit 2 = suppression leaked.
using AgentRuleLint

const ROOT = normpath(joinpath(@__DIR__, ".."))
path = joinpath("test", "corpus", "expect_text_blank_line.yml")
res = AgentRuleLint.check(ROOT; paths = [path])
ok = any(
    d ->
    d.rule_id == "project/no-internal-codename" &&
        d.path == path &&
        !d.suppressed,
    res.violations,
)
exit(ok ? 0 : 2)
