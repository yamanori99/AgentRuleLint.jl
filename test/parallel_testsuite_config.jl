# Suite discovery exclusions for ParallelTestRunner (included from runtests.jl).

const _MUTATION_HELPER_ONLY_TESTS = Set(
    [
        "test_expect_text_mutation_blank",
        "test_expect_text_mutation_malformed",
        "test_expect_text_mutation_unanchored",
        "test_explain_invalid_config",
        "test_integrity_mutation_broad_throws",
        "test_integrity_mutation_exit",
        "test_integrity_mutation_runtests",
        "test_integrity_mutation_skip",
        "test_integrity_mutation_tol",
        "test_integrity_mutation_trivial",
        "test_silent_catch_mutation_detector",
    ],
)

const _PROBE_ONLY_TESTS = Set(["test_digest_deliberate_fail"])
