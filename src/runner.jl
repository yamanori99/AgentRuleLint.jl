function _unique_violations(diags::Vector{Violation})
    seen = Set{Tuple{String, Span, String, String, Bool}}()
    out = Violation[]
    for d in diags
        key = (d.path, d.span, d.rule_id, d.message, d.suppressed)
        key in seen && continue
        push!(seen, key)
        push!(out, d)
    end
    return out
end

function discover_files(root::AbstractString; paths = String[], diff_base = nothing)
    root = abspath(String(root))
    if !isempty(paths)
        out = String[]
        for p in paths
            ap = isabspath(p) ? p : joinpath(root, p)
            if isfile(ap)
                endswith(ap, ".jl") || continue
                push!(out, relpath(ap, root))
            elseif isdir(ap)
                for (dir, _, files) in walkdir(ap)
                    for f in files
                        endswith(f, ".jl") || continue
                        push!(out, relpath(joinpath(dir, f), root))
                    end
                end
            end
        end
        return sort(unique(replace.(out, '\\' => '/')))
    end
    diff_paths = diff_base === nothing ? String[] : resolve_diff_paths(root; base = diff_base)
    !isempty(diff_paths) && return sort(filter(p -> endswith(p, ".jl"), diff_paths))
    out = String[]
    for (dir, _, files) in walkdir(root)
        for f in files
            endswith(f, ".jl") || continue
            push!(out, relpath(joinpath(dir, f), root))
        end
    end
    out = sort(unique(replace.(out, '\\' => '/')))
    if isempty(paths) && diff_base === nothing
        filter!(p -> !startswith(p, "test/fixtures/"), out)
    end
    return out
end

function read_parsed_file(root::AbstractString, relpath::AbstractString)
    ap = joinpath(root, relpath)
    !isfile(ap) && throw(ParseError("file not found: $relpath"))
    raw = read(ap, String)
    norm = normalize_source(raw)
    return ParsedFile(String(relpath), raw, norm)
end

function build_file_context(root::AbstractString, relpath::AbstractString)
    parsed = read_parsed_file(root, relpath)
    parse_source(parsed.normalized; filename = parsed.path)
    expects = extract_expect_lines(parsed.normalized)
    return FileContext(parsed, expects, Violation[])
end

function is_violation_hit(d::Violation)
    d.suppressed && return false
    d.expect_status == :fulfilled && return false
    d.level == :allow && return false
    return true
end

function run_check(root::AbstractString; kwargs...)
    policy = resolve_policy(
        root;
        config_path = get(kwargs, :config_path, nothing),
        config_from = get(kwargs, :config_from, nothing),
    )
    init_registry!(policy)
    paths_kw = get(kwargs, :paths, String[])
    diff_base = get(kwargs, :diff_base, nothing)
    rel_files = discover_files(root; paths = paths_kw, diff_base = diff_base)

    contexts = FileContext[build_file_context(root, rel) for rel in rel_files]
    all_diags = Violation[]

    for fc in contexts
        append!(all_diags, expect_audit_diagnostics(fc, policy))
        append!(all_diags, forbid_rule_suppression_attempt(fc.expects, policy, fc))
        append!(all_diags, run_project_rules(fc, policy))
    end

    used_total = Set{Int}()
    for (fc, rel) in zip(contexts, rel_files)
        path_diags = Violation[]
        idxs = Int[]
        for (di, d) in enumerate(all_diags)
            d.path == rel || continue
            push!(idxs, di)
            push!(path_diags, d)
        end
        used = apply_expect_suppression!(path_diags, fc.expects, fc.parsed.normalized)
        for (j, di) in enumerate(idxs)
            all_diags[di] = path_diags[j]
        end
        union!(used_total, used)
    end

    for fc in contexts
        append!(all_diags, unused_expect_diagnostics(fc.expects, used_total, fc, policy))
    end

    all_diags = _unique_violations(all_diags)
    all_diags = sort(all_diags; by = d -> (d.path, d.span, d.rule_id))

    vcount = count(is_violation_hit, all_diags)
    scount = count(d -> d.suppressed, all_diags)
    exit = vcount > 0 ? 1 : 0
    return CheckResult(
        all_diags,
        true,
        exit,
        policy.config_source,
        policy.max_hits_per_rule,
        scount,
        vcount,
    )
end

function ratchet_write!(root::AbstractString, result::CheckResult)
    path = joinpath(abspath(root), ".jailint/ceilings.toml")
    mkpath(dirname(path))
    counts = Dict{String, Dict{String, Int}}()
    for d in result.violations
        is_violation_hit(d) || continue
        key = d.rule_id
        counts[key] = get(counts, key, Dict{String, Int}())
        counts[key][d.path] = get(counts[key], d.path, 0) + 1
    end
    lines = String[
        "# Updated via jailint ratchet --write",
        "# Monotonic non-increasing semantics apply on manual review.",
    ]
    for (rid, paths) in sort(collect(counts))
        push!(lines, "")
        push!(lines, "[violations.\"$rid\"]")
        for (p, c) in sort(collect(paths))
            push!(lines, "\"$p\" = $c")
        end
    end
    write(path, join(lines, '\n') * '\n')
    return path
end
