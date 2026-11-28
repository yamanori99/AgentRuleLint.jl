include("mutation_lib.jl")

run_source_mutation(;
    name = "src process-env access guard",
    rel_path = "src/runner.jl",
    needle = raw"root = abspath(String(root))",
    replacement = raw"""_ = get(ENV, "AGENTRULELINT_PROBE", "")
    root = abspath(String(root))""",
    replace_count = 1,
    verify = root -> begin
        script = join(
            [
                "using Test",
                "using AgentRuleLint",
                "const ROOT = $(repr(root))",
                "withenv(\"AGENTRULELINT_ENV_GUARD_PROBE\" => \"1\") do",
                "    include(joinpath(ROOT, \"test\", \"test_no_process_env_access.jl\"))",
                "end",
                "v = Main.collect_src_process_env_violations(ROOT)",
                "isempty(v) ? exit(0) : exit($(_MUTATION_VERIFY_DETECTED_EXIT))",
            ],
            '\n',
        )
        return mutation_verify_script(root, script; dir = root)
    end,
)
