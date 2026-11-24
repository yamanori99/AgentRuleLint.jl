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
    "silent-catch" => r"^(try|catch)\b",
    "unsafe-boundary" => r"^(@eval\b|ccall\b|@ccall\b|unsafe_\w+)",
    "test-integrity" => r"^@test",
    "shell-safety/process-pattern" => r"^(run\(|`|\bCmd\()",
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

"""
    resolve_expect_anchor_line(group, source) -> (anchor_line::Int, mismatch::Bool)

Anchor line for a contiguous expect group: first non-blank code line after the group
that matches at least one `rule_ref` in the group. If the first such line matches none,
`mismatch` is true and anchor_line is that line (suppression will not apply).
"""
function resolve_expect_anchor_line(group::Vector{ExpectLine}, source::AbstractString)
    isempty(group) && return 0, false
    last_e = maximum(e.line for e in group)
    li = first_code_line_after(source, last_e)
    li == 0 && return 0, false
    lines = split(normalize_source(source), '\n')
    code = code_prefix_on_line(lines[li])
    matched = any(rule_anchor_matches(ex.rule_ref, code) for ex in group)
    return li, !matched
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
