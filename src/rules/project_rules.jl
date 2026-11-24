function _simple_glob_match(path::String, pattern::String)
    if pattern == "**"
        return true
    end
    if endswith(pattern, "/**")
        prefix = pattern[1:(end - 3)]
        return startswith(path, prefix * "/") || path == prefix
    end
    if occursin('*', pattern)
        esc = Regex.escape(pattern)
        rx = Regex("^" * replace(esc, "\\*" => ".*") * "\$")
        return occursin(rx, path)
    end
    return path == pattern || basename(path) == pattern
end

function path_matches_glob(path::AbstractString, globs::Vector{String})
    p = replace(String(path), '\\' => '/')
    return any(g -> _simple_glob_match(p, String(g)), globs)
end

function _effective_project_level(policy::PolicyBundle, pr::ProjectRule)
    lvl = pr.level
    if lvl == :allow
        return if policy.on_allow_rule == :error
            :forbid
        elseif policy.on_allow_rule == :warn
            :warn
        else
            :allow
        end
    end
    return lvl
end

function run_project_rules(fc::FileContext, policy::PolicyBundle)
    path = fc.parsed.path
    source = fc.parsed.normalized
    diags = Violation[]
    tree = parse_source(source; filename = path)
    folds = collect_folded_string_exprs(tree, source)
    occ_idx = Dict{String, Int}()

    for pr in policy.project_rules
        path_matches_glob(path, pr.paths) || continue
        rule_id = project_rule_id(pr)
        eff_level = _effective_project_level(policy, pr)
        eff_level == :allow && continue

        for lit in pr.forbid_literals
            seen_spans = Set{Tuple{Int, Int}}()
            for fold in folds
                occursin(lit, fold.value) || continue
                keyspan = (fold.byte_start, fold.byte_end)
                keyspan in seen_spans && continue
                push!(seen_spans, keyspan)
                occ_idx[rule_id] = get(occ_idx, rule_id, 0) + 1
                idx = occ_idx[rule_id]
                sp = span_from_byte_range(source, fold.byte_start, fold.byte_end)
                anchor = sp.start_line
                msg = "forbidden literal matched (folded)"
                fp = diagnostic_fingerprint(rule_id, path, anchor, msg, idx)
                push!(
                    diags,
                    Violation(
                        rule_id,
                        :project,
                        eff_level,
                        path,
                        sp,
                        anchor,
                        fp,
                        :none,
                        false,
                        msg,
                        pr.intent,
                        pr.do_not,
                    ),
                )
            end
            for (c, p) in _child_positions(tree, 1)[1]
                summary(c) == "string" || continue
                raw = _collect_string_chars(c, source, p)
                raw === nothing && continue
                occursin(lit, raw) || continue
                occ_idx[rule_id] = get(occ_idx, rule_id, 0) + 1
                idx = occ_idx[rule_id]
                sp = span_from_byte_range(source, p, p + span(c) - 1)
                anchor = sp.start_line
                msg = "forbidden literal matched"
                fp = diagnostic_fingerprint(rule_id, path, anchor, msg, idx)
                push!(
                    diags,
                    Violation(
                        rule_id,
                        :project,
                        eff_level,
                        path,
                        sp,
                        anchor,
                        fp,
                        :none,
                        false,
                        msg,
                        pr.intent,
                        pr.do_not,
                    ),
                )
            end
        end
    end
    return diags
end
