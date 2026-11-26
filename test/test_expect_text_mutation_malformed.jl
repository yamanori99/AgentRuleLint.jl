# Detector helper for extract_expect_lines_text malformed acceptance mutation.
# exit 0 = malformed expects still excluded; exit 2 = malformed entries accepted.
using AgentRuleLint

src = "# agentrulelint-expect: project/no-internal-codename reason=\"\"\nval = 1\n"
ok = isempty(AgentRuleLint.extract_expect_lines_text(src))
exit(ok ? 0 : 2)
