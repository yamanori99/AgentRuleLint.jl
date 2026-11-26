include("mutation_lib.jl")

run_source_mutation(;
    name = "expect text unanchored eligibility",
    rel_path = "src/expect.jl",
    needle = "        for ex in g\n            rule_anchor_matches(ex.rule_ref, code) || continue\n            push!(eligible, ex)\n        end\n    end\n    return eligible\nend\n\nfunction expect_audit_diagnostics(fc::FileContext, policy::PolicyBundle)\n",
    replacement = "        for ex in g\n            push!(eligible, ex)\n        end\n    end\n    return eligible\nend\n\nfunction expect_audit_diagnostics(fc::FileContext, policy::PolicyBundle)\n",
    verify = root -> begin
        cmd = _julia_project_cmd(root, "test/test_expect_text_mutation_unanchored.jl")
        return detector_disabled(cmd; dir = root)
    end,
)
