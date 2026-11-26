# Detector helper for text-path unanchored eligibility mutation.
# exit 0 = short-form expect still does not suppress; exit 2 = suppression leaked.
using AgentRuleLint

const ROOT = normpath(joinpath(@__DIR__, ".."))
path = joinpath("test", "corpus", "expect_text_anchor_mismatch.sh")
res = AgentRuleLint.check(ROOT; paths = [path])
ok = any(
    d ->
    d.rule_id == "project/no-internal-codename" &&
        d.path == path &&
        !d.suppressed,
    res.violations,
)
exit(ok ? 0 : 2)
