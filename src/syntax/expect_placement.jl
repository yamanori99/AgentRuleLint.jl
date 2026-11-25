using JuliaSyntax: GreenNode, children, head, kind, span

const _CALL_SUMMARIES = ("call", "inertquote", "macrocall", "macro")

"""Code portion of a source line (before an end-of-line `#` comment)."""
function code_prefix_on_line(line::AbstractString)
    idx = findfirst('#', line)
    return idx === nothing ? strip(line) : strip(line[1:prevind(line, idx)])
end

"""Whether `line_code` is a `catch` clause header line."""
function line_is_catch_header(line_code::AbstractString)
    code = strip(line_code)
    return startswith(code, "catch") && occursin(r"^catch\b", code)
end

const _RULE_ANCHOR_RX = Dict(
    # Suppression anchors on the guarded construct (`try`), not on `catch` (placement above catch is forbidden).
    "silent-catch" => r"^try\b",
    "unsafe-boundary" =>
        r"^(@eval\b|@inbounds\b|@generated\b|ccall\b|@ccall\b|Meta\.parse|invokelatest|getfield\(|getproperty\(|unsafe_\w+)",
    "test-integrity" => r"^@test",
    "shell-safety/process-pattern" => r"^(run\(|open\(|read\(|pipeline\(|\bCmd\(|`)",
)

"""
    rule_anchor_matches(rule_ref, line_code) -> Bool

Whether non-blank code on a line is a valid suppression anchor for `rule_ref`.
Unknown built-in slugs fail closed (no match). Project rules accept any non-empty code line.
"""
function rule_anchor_matches(rule_ref::AbstractString, line_code::AbstractString)
    code = strip(String(line_code))
    isempty(code) && return false
    ref = strip(String(rule_ref))
    startswith(ref, "project/") && return true
    ref == "expect-audit" && return false
    rx = get(_RULE_ANCHOR_RX, ref, nothing)
    rx === nothing && return false
    return occursin(rx, code)
end

"""First non-blank code line index strictly after `last_line`, or 0."""
function first_code_line_after(source::AbstractString, last_line::Int)
    lines = split(normalize_source(source), '\n')
    for li in (last_line + 1):length(lines)
        !isempty(code_prefix_on_line(lines[li])) && return li
    end
    return 0
end

"""Anchor line for a contiguous expect block: first non-blank code line after the last expect."""
function group_attachment_code_line(group::Vector{ExpectLine}, source::AbstractString)
    isempty(group) && return 0, ""
    src = normalize_source(source)
    last_e = maximum(e.line for e in group)
    li = first_code_line_after(src, last_e)
    li == 0 && return 0, ""
    lines = split(src, '\n')
    return li, code_prefix_on_line(lines[li])
end

"""
    expects_eligible_for_suppression(expects, source) -> Vector{ExpectLine}

Fail-closed: forbidden or mis-anchored expects are excluded before suppression runs.
"""
function expects_eligible_for_suppression(expects::Vector{ExpectLine}, source::AbstractString)
    isempty(expects) && return ExpectLine[]
    src = normalize_source(source)
    runic_regions = runic_off_regions(src)
    call_arg_lines = multiline_call_interior_lines(src)
    eligible = ExpectLine[]
    for g in contiguous_expect_groups(expects)
        anchor_li, code = group_attachment_code_line(g, src)
        anchor_li == 0 && continue
        last_e = maximum(e.line for e in g)
        anchor_li > last_e + 1 && continue
        line_is_catch_header(code) && continue
        for ex in g
            line_in_runic_off_region(ex.line, runic_regions) && continue
            ex.line in call_arg_lines && continue
            rule_anchor_matches(ex.rule_ref, code) || continue
            push!(eligible, ex)
        end
    end
    return eligible
end

function _walk_green(node::GreenNode, pos::Int, src::AbstractString, out::Set{Int})
    s = summary(node)
    if s in _CALL_SUMMARIES
        byte_end = pos + span(node) - 1
        byte_end = min(byte_end, ncodeunits(src))
        start_line = line_number_at_byte(src, pos)
        end_line = line_number_at_byte(src, byte_end)
        if end_line > start_line
            for li in (start_line + 1):(end_line - 1)
                push!(out, li)
            end
        end
    end
    ch = children(node)
    ch === nothing && return
    cpos = pos
    for c in ch
        _walk_green(c, cpos, src, out)
        cpos += span(c)
    end
    return
end

"""Lines that lie strictly inside a multiline call-like expression (argument region)."""
function multiline_call_interior_lines(source::AbstractString)
    src = normalize_source(source)
    tree = parse_source(src)
    out = Set{Int}()
    _walk_green(tree, 1, src, out)
    return out
end

"""Tracks `# runic: off` … `# runic: on` regions; end comment is inclusive."""
function runic_off_regions(source::AbstractString)
    src = normalize_source(source)
    lines = split(src, '\n')
    regions = Vector{Tuple{Int, Int}}()
    off = 0
    for (li, line) in enumerate(lines)
        body = strip(line)
        if occursin(r"(?i)^#\s*runic:\s*off\b", body)
            off = li
        elseif off > 0 && occursin(r"(?i)^#\s*runic:\s*on\b", body)
            push!(regions, (off, li))
            off = 0
        end
    end
    off > 0 && push!(regions, (off, length(lines)))
    return regions
end

function line_in_runic_off_region(line_no::Int, regions::Vector{Tuple{Int, Int}})
    for (a, b) in regions
        line_no in a:b && return true
    end
    return false
end
