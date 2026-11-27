# Paths the default Pkg.test suite may create or modify; excluded from the
# post-suite `git status --porcelain --untracked-files=all` guard in test_src_untouched.
const SUITE_GIT_STATUS_EXCLUSIONS = ("test/last_failures.txt",)
