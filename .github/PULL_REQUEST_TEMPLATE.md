## Summary

<!-- What changed and why. -->

## Test plan

Canonical local gate: [`.agents/skills/pre-push-gate/SKILL.md`](../.agents/skills/pre-push-gate/SKILL.md) (`julia +1.13`).

- [ ] Pre-push gate: Runic, trailing newlines, `git diff --check`, JETLS (`--exit-severity=hint`), `Pkg.test()` (`pipefail` + `tee`), `test/mutation/run_all.jl` (all PASS), `git merge-tree --write-tree origin/main HEAD`
- [ ] CI green on this head (or only `protected-paths` red per interim procedure)

## Protected paths changed

<!--
List every protected path this PR changes, or write `none`.
Until #70 lands an approval path, PRs that touch protected paths must:
- keep every check green except `protected-paths`
- list those paths here exactly matching the `protected-paths` findings
- be merged manually by the owner (agents never merge or approve)
See CONTRIBUTING.md → "Interim: merging changes that trip protected-paths".
-->

- none
