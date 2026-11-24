#!/usr/bin/env bash
# Latest registered Aqua in a temp env (not test/Project.toml). Same as CI Aqua job.
#
#   ./.github/aqua-check.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

exec julia --startup-file=no -e '
using Pkg
Pkg.activate(; temp=true)
Pkg.develop(PackageSpec(; path=pwd()))
Pkg.add("Aqua")
using Aqua, JAILint
Aqua.test_all(JAILint)
'
