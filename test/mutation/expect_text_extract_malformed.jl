include("mutation_lib.jl")

run_source_mutation(;
    name = "expect text extract accepts malformed",
    rel_path = "src/expect.jl",
    # First occurrence is extract_expect_lines_text; Julia extract is later.
    needle = "        parsed === nothing && continue\n        parsed.status == :malformed && continue\n        parsed.status != :ok && continue\n        push!(expects, ExpectLine(line_no, parsed.rule_ref, parsed.reason, body))\n",
    replacement = "        parsed === nothing && continue\n        push!(expects, ExpectLine(line_no, parsed.rule_ref, parsed.reason, body))\n",
    replace_count = 1,
    verify = root -> begin
        cmd = _julia_project_cmd(root, "test/test_expect_text_mutation_malformed.jl")
        return detector_disabled(cmd; dir = root)
    end,
)
