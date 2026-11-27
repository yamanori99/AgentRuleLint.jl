include("mutation_lib.jl")

run_source_mutation(;
    name = "unused expect line-only used set",
    rel_path = "src/runner.jl",
    needle = """    used_by_path = Dict{String, Set{Int}}()
        for (fc, rel) in zip(contexts, rel_files)
            path_diags = Violation[]
            idxs = Int[]
            for (di, d) in enumerate(all_diags)
                d.path == rel || continue
                push!(idxs, di)
                push!(path_diags, d)
            end
            eligible = if julia_source_path(rel)
                expects_eligible_for_suppression(fc.expects, fc.parsed.normalized; tree = fc.tree)
            else
                expects_eligible_for_suppression_text(fc.expects, fc.parsed.normalized)
            end
            used = apply_expect_suppression!(path_diags, eligible, fc.parsed.normalized)
            for (j, di) in enumerate(idxs)
                all_diags[di] = path_diags[j]
            end
            used_by_path[rel] = used
        end

        for fc in contexts
            used = used_by_path[fc.parsed.path]
            append!(all_diags, unused_expect_diagnostics(fc.expects, used, fc, policy, all_diags))
        end
    """,
    replacement = """    used_total = Set{Int}()
        for (fc, rel) in zip(contexts, rel_files)
            path_diags = Violation[]
            idxs = Int[]
            for (di, d) in enumerate(all_diags)
                d.path == rel || continue
                push!(idxs, di)
                push!(path_diags, d)
            end
            eligible = if julia_source_path(rel)
                expects_eligible_for_suppression(fc.expects, fc.parsed.normalized; tree = fc.tree)
            else
                expects_eligible_for_suppression_text(fc.expects, fc.parsed.normalized)
            end
            used = apply_expect_suppression!(path_diags, eligible, fc.parsed.normalized)
            for (j, di) in enumerate(idxs)
                all_diags[di] = path_diags[j]
            end
            union!(used_total, used)
        end

        for fc in contexts
            append!(all_diags, unused_expect_diagnostics(fc.expects, used_total, fc, policy, all_diags))
        end
    """,
    verify = root -> mutation_verify_driver(
        root,
        "test/test_unused_expect_mutation_line_only.jl";
        dir = root,
    ),
)
