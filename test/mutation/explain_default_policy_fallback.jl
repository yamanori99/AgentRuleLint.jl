include("mutation_lib.jl")

run_source_mutation(;
    name = "explain default_policy fallback",
    rel_path = "src/format/report.jl",
    needle = "policy = resolve_policy(root)",
    replacement = "policy = try resolve_policy(root) catch; default_policy(root) end",
    # After inactive-builtin explain, both explain_rule_unknown and explain_rule
    # call resolve_policy; patching only the first leaves ConfigError intact.
    replace_count = typemax(Int),
    verify = root -> mutation_verify_driver(root, "test/test_explain_invalid_config.jl"; dir = root),
)
