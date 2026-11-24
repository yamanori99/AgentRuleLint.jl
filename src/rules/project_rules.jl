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

function line_number_at_byte(source::AbstractString, byte_index::Int)
    line = 1
    pos = 1
    while pos < byte_index && pos <= ncodeunits(source)
        nl = findnext('\n', source, pos)
        nl === nothing && break
        if nl < byte_index
            line += 1
            pos = nl + 1
        else
            break
        end
    end
    return line
end

function col_at_byte(source::AbstractString, line::Int, byte_index::Int)
    start, line_text, _ = line_byte_span(source, line)
    return max(1, byte_index - start + 1)
end

function run_project_rules(fc::FileContext, policy::PolicyBundle)
    path = fc.parsed.path
    source = fc.parsed.normalized
    diags = Diagnostic[]
    parse_source(source; filename = path)
    occ = Dict{String, Int}()
    for pr in policy.project_rules
        path_matches_glob(path, pr.paths) || continue
        rule_id = project_rule_id(pr)
        for lit in pr.forbid_literals
            # whole-file folded strings
            folds = folded_string_literals(parse_source(source; filename = path), source)
            raw_hit = occursin(lit, source)
            for val in folds
                (occursin(lit, val) || raw_hit) || continue
                key = rule_id
                occ[key] = get(occ, key, 0) + 1
                idx = occ[key]
                anchor = 1
                for (ln, line) in enumerate(split(source, '\n'))
                    (occursin(lit, line) || occursin(lit, strip(line))) || continue
                    anchor = ln
                    hit = findnext(lit, line, 1)
                    hit === nothing && continue
                    sc = max(1, hit isa Integer ? hit : first(hit))
                    ec = sc + ncodeunits(lit) - 1
                    span = Span(ln, sc, ln, ec)
                    msg = "forbidden literal matched"
                    fp = diagnostic_fingerprint(rule_id, path, anchor, msg, idx)
                    push!(
                        diags,
                        Diagnostic(
                            rule_id,
                            :project,
                            pr.level,
                            path,
                            span,
                            anchor,
                            fp,
                            :none,
                            false,
                            msg,
                            pr.intent,
                            pr.do_not,
                        ),
                    )
                    break
                end
            end
        end
    end
    return diags
end

function anchor_tokens_for_diagnostic(d::Diagnostic, source::AbstractString)
    line = d.anchor_line
    lines = split(source, '\n')
    line > length(lines) && return String[]
    tokens = split(strip(lines[line]))
    return tokens
end
