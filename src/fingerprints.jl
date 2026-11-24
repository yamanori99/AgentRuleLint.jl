using SHA

const PATH_LEVEL_ANCHOR_MARKER = "<path>"

function normalize_anchor_tokens(message::String)
    parts = filter(!isempty, split(strip(message)))
    return join(parts, " ")
end

function normalize_anchor_source_text(raw::AbstractString)
    parts = filter(!isempty, split(strip(String(raw))))
    return isempty(parts) ? "" : join(parts, " ")
end

"""Anchor text from pre-split normalized source lines (`Span` columns are codepoints)."""
function violation_anchor_text(lines::Vector{String}, d::Violation)
    sp = d.span
    sp.start_line < 1 && return PATH_LEVEL_ANCHOR_MARKER
    sp.start_line > length(lines) && return PATH_LEVEL_ANCHOR_MARKER
    if sp.start_line == sp.end_line
        line = lines[sp.start_line]
        sc = max(1, sp.start_col)
        ec = max(sc, sp.end_col)
        return normalize_anchor_source_text(slice_line_codepoint_cols(line, sc, ec))
    end
    parts = String[]
    for ln in sp.start_line:min(sp.end_line, length(lines))
        line = lines[ln]
        if ln == sp.start_line
            sc = max(1, sp.start_col)
            push!(parts, slice_line_codepoint_cols(line, sc, length(line)))
        elseif ln == sp.end_line
            ec = max(1, sp.end_col)
            push!(parts, slice_line_codepoint_cols(line, 1, ec))
        else
            push!(parts, line)
        end
    end
    return normalize_anchor_source_text(join(parts, " "))
end

function diagnostic_fingerprint(
        rule_id::String,
        path::String,
        anchor_text::String,
        message::String,
        index::Int,
    )
    payload =
        "v1:$(rule_id)|$(path)|$(anchor_text)|$(normalize_anchor_tokens(message))|$(index)"
    return "v1:" * bytes2hex(sha1(payload))
end

function _violation_with_fingerprint(d::Violation, fp::String)
    return Violation(
        d.rule_id,
        d.origin,
        d.level,
        d.path,
        d.span,
        d.anchor_line,
        fp,
        d.expect_status,
        d.suppressed,
        d.message,
        d.intent,
        d.do_not,
    )
end

"""
    assign_diagnostic_fingerprints!(diags, sources)

Assign line-independent fingerprints and per-file occurrence indices in source order.
`sources` maps repo-relative path → normalized file source.
"""
function assign_diagnostic_fingerprints!(diags::Vector{Violation}, sources::Dict{String, String})
    by_path = Dict{String, Vector{Int}}()
    for (i, d) in enumerate(diags)
        push!(get!(by_path, d.path, Int[]), i)
    end
    for (path, idxs) in by_path
        raw = get(sources, path, "")
        norm = normalize_source(raw)
        lines = String[String(l) for l in split(norm, '\n')]
        sort!(idxs; by = i -> (diags[i].span, diags[i].rule_id, diags[i].message))
        occ = Dict{Tuple{String, String, String}, Int}()
        for i in idxs
            d = diags[i]
            anchor = violation_anchor_text(lines, d)
            msg = normalize_anchor_tokens(d.message)
            key = (d.rule_id, anchor, msg)
            occ[key] = get(occ, key, 0) + 1
            idx = occ[key]
            fp = diagnostic_fingerprint(d.rule_id, path, anchor, d.message, idx)
            diags[i] = _violation_with_fingerprint(d, fp)
        end
    end
    return nothing
end

function pattern_hash(snippet::String)
    return "v1:" * bytes2hex(sha1(snippet))
end
