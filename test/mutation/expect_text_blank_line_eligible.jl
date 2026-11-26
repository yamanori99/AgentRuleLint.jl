include("mutation_lib.jl")

run_source_mutation(;
    name = "expect text blank-line eligibility",
    rel_path = "src/expect.jl",
    needle = "function expects_eligible_for_suppression_text(expects::Vector{ExpectLine}, source::AbstractString)\n    isempty(expects) && return ExpectLine[]\n    src = normalize_source(source)\n    eligible = ExpectLine[]\n    for g in contiguous_expect_groups(expects)\n        anchor_li, code = group_attachment_code_line(g, src)\n        anchor_li == 0 && continue\n        last_e = maximum(e.line for e in g)\n        anchor_li > last_e + 1 && continue\n        for ex in g\n            rule_anchor_matches(ex.rule_ref, code) || continue\n",
    replacement = "function expects_eligible_for_suppression_text(expects::Vector{ExpectLine}, source::AbstractString)\n    isempty(expects) && return ExpectLine[]\n    src = normalize_source(source)\n    eligible = ExpectLine[]\n    for g in contiguous_expect_groups(expects)\n        anchor_li, code = group_attachment_code_line(g, src)\n        anchor_li == 0 && continue\n        last_e = maximum(e.line for e in g)\n        for ex in g\n            rule_anchor_matches(ex.rule_ref, code) || continue\n",
    verify = root -> begin
        cmd = _julia_project_cmd(root, "test/test_expect_text_mutation_blank.jl")
        return detector_disabled(cmd; dir = root)
    end,
)
