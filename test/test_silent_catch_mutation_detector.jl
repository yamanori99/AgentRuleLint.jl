# Detector helper for silent-catch source mutations (temp copy only).
# exit 0 = corpus still flagged; exit 2 = detector disabled by mutation.
using AgentRuleLint

isempty(ARGS) && exit(3)
corpus = joinpath("test", "corpus", ARGS[1])
res = AgentRuleLint.check("."; paths = [corpus])
ok = any(d -> d.rule_id == "silent-catch" && !d.suppressed, res.violations)
exit(ok ? 0 : 2)
