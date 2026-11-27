# Git-backed diff scope for `--diff` (first-parent / explicit base ref, fail-closed).

const DEFAULT_DIFF_BASE = "HEAD^1"

struct DiffFileContext
    path::String
    changed_lines::Set{Int}
    status::Char
end

struct DiffScope
    base_ref::String
    files::Vector{DiffFileContext}
end

"""Single path from `git diff --name-status` (rename/copy records both `path` and `old_path`)."""
struct DiffPathEvent
    status::Char
    path::String
    old_path::String
end

const _DIFF_NAME_STATUS_SINGLE = Set(['A', 'M', 'D', 'T'])
const _DIFF_NAME_STATUS_PAIR = Set(['R', 'C'])

function _git_root(path::AbstractString)
    root = abspath(String(path))
    isdir(root) || throw(GitError("not a directory: $root"))
    cmd = Cmd(["git", "-C", root, "rev-parse", "--show-toplevel"])
    try
        return strip(String(_read_git_cmd(cmd; error_prefix = "not a git repository: $root")))
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && rethrow()
        throw(GitError("not a git repository: $root: $(format_error(err))"))
    end
end

function normalize_path(p::AbstractString)
    s = replace(String(p), '\\' => '/')
    startswith(s, "./") && (s = s[3:end])
    return s
end

function verify_diff_base_ref(root::AbstractString, base::AbstractString)
    root = _git_root(root)
    ref = String(base)
    spec = string(ref, "^{commit}")
    cmd = Cmd(["git", "-C", root, "rev-parse", "--verify", "--end-of-options", spec])
    prefix = if ref == DEFAULT_DIFF_BASE
        "diff base ref not available: HEAD^1 (shallow clone or single-parent HEAD)"
    else
        "diff base ref not available: $ref"
    end
    try
        _read_git_cmd(cmd; error_prefix = prefix)
        return ref
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && rethrow()
        throw(GitError("$prefix: $(format_error(err))"))
    end
end

function resolve_diff_base_arg(raw)
    raw === nothing && return nothing
    return strip(String(raw))
end

function _git_diff_name_status_cmd(root::AbstractString, base::AbstractString)
    return Cmd(
        [
            "git",
            "-C",
            root,
            "-c",
            "diff.renames=true",
            "diff",
            "-z",
            "-M",
            "--no-ext-diff",
            "--no-textconv",
            "--text",
            "--name-status",
            "--end-of-options",
            base,
        ],
    )
end

function _parse_diff_name_status_z(parts::Vector{SubString{String}})
    i = 1
    singles = Tuple{Char, String}[]
    events = DiffPathEvent[]
    while i <= length(parts)
        status = String(parts[i])
        isempty(status) &&
            throw(GitError("malformed git diff name-status: empty status entry"))
        st = status[1]
        i += 1
        if st in _DIFF_NAME_STATUS_PAIR
            i + 1 > length(parts) &&
                throw(GitError("truncated git diff name-status record for status '$status'"))
            oldp = normalize_path(parts[i])
            newp = normalize_path(parts[i + 1])
            i += 2
            push!(singles, (st, newp))
            push!(events, DiffPathEvent(st, newp, oldp))
        elseif st in _DIFF_NAME_STATUS_SINGLE
            i > length(parts) &&
                throw(GitError("truncated git diff name-status record for status '$status'"))
            path = normalize_path(parts[i])
            i += 1
            push!(singles, (st, path))
            push!(events, DiffPathEvent(st, path, ""))
        else
            throw(GitError("unknown git diff name-status '$status'"))
        end
    end
    singles = unique(singles)
    return singles, events
end

function _parse_diff_name_status_payload(payload::AbstractString)
    parts = split(String(payload), '\0'; keepempty = false)
    singles, _ = _parse_diff_name_status_z(parts)
    return singles
end

function _parse_diff_path_events_payload(payload::AbstractString)
    parts = split(String(payload), '\0'; keepempty = false)
    _, events = _parse_diff_name_status_z(parts)
    return events
end

function git_diff_name_status(root::AbstractString, base::AbstractString)
    root = _git_root(root)
    base = verify_diff_base_ref(root, base)
    cmd = _git_diff_name_status_cmd(root, base)
    prefix = "git diff failed for base=$(base)"
    bytes = try
        _read_git_cmd(cmd; error_prefix = prefix)
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && rethrow()
        throw(GitError("$prefix: $(format_error(err))"))
    end
    isempty(bytes) && return Tuple{Char, String}[]
    return _parse_diff_name_status_payload(String(bytes))
end

function git_diff_path_events(root::AbstractString, base::AbstractString)
    root = _git_root(root)
    base = verify_diff_base_ref(root, base)
    cmd = _git_diff_name_status_cmd(root, base)
    prefix = "git diff failed for base=$(base)"
    bytes = try
        _read_git_cmd(cmd; error_prefix = prefix)
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && rethrow()
        throw(GitError("$prefix: $(format_error(err))"))
    end
    isempty(bytes) && return DiffPathEvent[]
    return _parse_diff_path_events_payload(String(bytes))
end

const _HUNK_RE = r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@"

function _parse_unified_hunks(body::AbstractString)
    lines = Set{Int}()
    for line in split(body, '\n'; keepempty = false)
        m = match(_HUNK_RE, line)
        m === nothing && continue
        cap1 = m.captures[1]
        cap1 === nothing && continue
        start_new = parse(Int, cap1)
        cap2 = m.captures[2]
        len = cap2 === nothing ? 1 : parse(Int, cap2)
        len > 0 || continue
        for ln in start_new:(start_new + len - 1)
            push!(lines, ln)
        end
    end
    return lines
end

function _numstat_line_binary(line::AbstractString)
    parts = split(String(line), '\t'; limit = 3)
    length(parts) >= 2 || return false
    return parts[1] == "-" && parts[2] == "-"
end

function _numstat_add_del(line::AbstractString)
    line = String(line)
    _numstat_line_binary(line) && return (0, 0)
    parts = split(line, '\t'; limit = 3)
    length(parts) >= 2 ||
        throw(GitError("malformed git diff --numstat line: $(repr(line))"))
    added = tryparse(Int, parts[1])
    deleted = tryparse(Int, parts[2])
    (added === nothing || deleted === nothing) &&
        throw(GitError("malformed git diff --numstat line: $(repr(line))"))
    return added, deleted
end

"""Sum add/del for a single-path or full `--numstat` payload (one or more lines)."""
function _numstat_totals(payload::AbstractString)
    added = 0
    deleted = 0
    any_binary = false
    for line in split(String(payload), '\n'; keepempty = false)
        _numstat_line_binary(line) && (any_binary = true; continue)
        a, d = _numstat_add_del(line)
        added += a
        deleted += d
    end
    return added, deleted, any_binary
end

function _parse_numstat_by_path(payload::AbstractString)
    out = Dict{String, String}()
    for line in split(String(payload), '\n'; keepempty = false)
        parts = split(line, '\t'; limit = 3)
        length(parts) >= 3 || continue
        out[normalize_path(parts[3])] = line
    end
    return out
end

function _diff_has_unified_hunk(body::AbstractString)
    for line in split(body, '\n'; keepempty = false)
        match(_HUNK_RE, line) === nothing || return true
    end
    return false
end

function _diff_has_content_delta(body::AbstractString)
    for line in split(body, '\n'; keepempty = false)
        (startswith(line, "+") && !startswith(line, "+++")) && return true
        (startswith(line, "-") && !startswith(line, "---")) && return true
    end
    return false
end

"""Unified diff has mode metadata only (no `@@` hunks)."""
function _diff_mode_only_metadata(body::AbstractString)
    _diff_has_unified_hunk(body) && return false
    for line in split(body, '\n'; keepempty = false)
        startswith(line, "old mode ") && return true
        startswith(line, "new mode ") && return true
    end
    return false
end

"""Unified diff has rename/copy metadata only (no content `+`/`-` lines)."""
function _diff_pure_rename_copy_metadata(body::AbstractString)
    _diff_has_unified_hunk(body) && return false
    _diff_has_content_delta(body) && return false
    for line in split(body, '\n'; keepempty = false)
        occursin("rename from", line) && return true
        occursin("rename to", line) && return true
        startswith(line, "copy from") && return true
        startswith(line, "copy to") && return true
        startswith(line, "similarity index ") && return true
    end
    return false
end

function _git_diff_numstat_cmd(
        root::AbstractString,
        base::AbstractString;
        text::Bool,
        path = nothing,
    )
    args = [
        "git",
        "-C",
        root,
        "diff",
        "--numstat",
        "--no-ext-diff",
        "--no-textconv",
    ]
    text && push!(args, "--text")
    append!(args, ["--end-of-options", base])
    path === nothing || append!(args, ["--", String(path)])
    return Cmd(args)
end

function _git_diff_numstat_maps(root::AbstractString, base::AbstractString, prefix::AbstractString)
    text_bytes = try
        _read_git_cmd(_git_diff_numstat_cmd(root, base; text = true); error_prefix = prefix)
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && rethrow()
        throw(GitError("$prefix: $(format_error(err))"))
    end
    probe_bytes = try
        _read_git_cmd(_git_diff_numstat_cmd(root, base; text = false); error_prefix = prefix)
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && rethrow()
        throw(GitError("$prefix: $(format_error(err))"))
    end
    return (
        _parse_numstat_by_path(String(text_bytes)),
        _parse_numstat_by_path(String(probe_bytes)),
    )
end

function _numstat_payload_for_path(map::Dict{String, String}, path::AbstractString)
    line = get(map, normalize_path(path), "")
    return isempty(line) ? "" : line * "\n"
end

"""
    _changed_lines_from_diff_output(body, numstat_text, numstat_probe, path) -> Set{Int}

Parse `git diff -U0 --text` into new-side line numbers. `numstat_probe` is `git diff
--numstat` without `--text` (binary paths use `-\\t-\\t`). Empty hunks are allowed
only for mode-only or pure rename/copy metadata; otherwise fail closed.
"""
function _changed_lines_from_diff_output(
        body::AbstractString,
        numstat_text::AbstractString,
        numstat_probe::AbstractString,
        path::AbstractString,
    )
    body = String(body)
    path = String(path)
    lines = _parse_unified_hunks(body)
    _, _, probe_binary = _numstat_totals(numstat_probe)
    if probe_binary && isempty(lines)
        throw(GitError("git diff numstat probe binary for path=$(path) (fail closed)"))
    end
    add, del, _ = _numstat_totals(numstat_text)
    if isempty(lines)
        _diff_mode_only_metadata(body) && return lines
        _diff_pure_rename_copy_metadata(body) && return lines
        (add > 0 || del > 0) &&
            throw(GitError("git diff numstat reports content change without hunks for path=$(path)"))
        _diff_has_content_delta(body) &&
            throw(GitError("git diff produced no changed lines for path=$(path) (fail closed)"))
    end
    return lines
end

function git_diff_changed_lines(
        root::AbstractString,
        base::AbstractString,
        relpath::AbstractString;
        numstat_text_map = nothing,
        numstat_probe_map = nothing,
    )
    root = _git_root(root)
    base = verify_diff_base_ref(root, base)
    path = normalize_path(relpath)
    unified = Cmd(
        [
            "git",
            "-C",
            root,
            "diff",
            "-U0",
            "--no-color",
            "--no-ext-diff",
            "--no-textconv",
            "--text",
            "--end-of-options",
            base,
            "--",
            path,
        ],
    )
    prefix = "git diff failed for base=$(base) path=$(path)"
    body = try
        String(_read_git_cmd(unified; error_prefix = prefix))
    catch err
        err isa InterruptException && rethrow()
        err isa GitError && rethrow()
        throw(GitError("$prefix: $(format_error(err))"))
    end
    numstat_text = if numstat_text_map === nothing
        try
            String(
                _read_git_cmd(
                    _git_diff_numstat_cmd(root, base; text = true, path = path);
                    error_prefix = prefix,
                ),
            )
        catch err
            err isa InterruptException && rethrow()
            err isa GitError && rethrow()
            throw(GitError("$prefix: $(format_error(err))"))
        end
    else
        _numstat_payload_for_path(numstat_text_map, path)
    end
    numstat_probe = if numstat_probe_map === nothing
        try
            String(
                _read_git_cmd(
                    _git_diff_numstat_cmd(root, base; text = false, path = path);
                    error_prefix = prefix,
                ),
            )
        catch err
            err isa InterruptException && rethrow()
            err isa GitError && rethrow()
            throw(GitError("$prefix: $(format_error(err))"))
        end
    else
        _numstat_payload_for_path(numstat_probe_map, path)
    end
    return _changed_lines_from_diff_output(body, numstat_text, numstat_probe, path)
end

function build_diff_scope(root::AbstractString, base::AbstractString)
    root = _git_root(root)
    base = verify_diff_base_ref(root, base)
    entries = git_diff_name_status(root, base)
    prefix = "git diff failed for base=$(base)"
    text_map, probe_map = _git_diff_numstat_maps(root, base, prefix)
    files = DiffFileContext[]
    for (st, path) in entries
        if st == 'D'
            push!(files, DiffFileContext(path, Set{Int}(), st))
            continue
        end
        lines = if st == 'A'
            ap = joinpath(root, path)
            if isfile(ap)
                n = count('\n', read(ap, String)) + 1
                Set{Int}(1:max(n, 1))
            else
                Set{Int}()
            end
        else
            git_diff_changed_lines(
                root,
                base,
                path;
                numstat_text_map = text_map,
                numstat_probe_map = probe_map,
            )
        end
        push!(files, DiffFileContext(path, lines, st))
    end
    return DiffScope(base, files)
end

function resolve_diff_paths(root::AbstractString; base = nothing, explicit_paths = String[])
    isempty(explicit_paths) || return normalize_path.(explicit_paths)
    base === nothing && return String[]
    return [p for (_, p) in git_diff_name_status(root, base)]
end

function diff_path_status(scope::DiffScope, relpath::AbstractString)
    path = normalize_path(relpath)
    for f in scope.files
        f.path == path && return f.status
    end
    return '\0'
end

function diff_changed_lines(scope::DiffScope, relpath::AbstractString)
    path = normalize_path(relpath)
    for f in scope.files
        f.path == path && return f.changed_lines
    end
    return Set{Int}()
end

function violation_on_changed_lines(d::Violation, changed::Set{Int})
    isempty(changed) && return false
    for ln in d.span.start_line:d.span.end_line
        ln in changed && return true
    end
    return d.anchor_line in changed
end

function _test_integrity_deleted_on_diff(d::Violation, scope::DiffScope, path_events::Vector{DiffPathEvent})
    d.rule_id != "test-integrity" && return false
    d.expect_status != :deleted_test && return false
    p = normalize_path(d.path)
    p != "test/runtests.jl" && !startswith(p, "test/") && return false
    st = diff_path_status(scope, d.path)
    st == 'D' && return true
    for ev in path_events
        ev.status == 'R' || continue
        normalize_path(ev.old_path) == p && return true
    end
    return false
end

function filter_diff_violations!(
        diags::Vector{Violation},
        scope::DiffScope,
        path_events::Vector{DiffPathEvent} = DiffPathEvent[],
    )
    out = Violation[]
    for d in diags
        st = diff_path_status(scope, d.path)
        if st == 'D'
            _test_integrity_deleted_on_diff(d, scope, path_events) && (push!(out, d); continue)
            continue
        end
        if _test_integrity_deleted_on_diff(d, scope, path_events)
            push!(out, d)
            continue
        end
        changed = diff_changed_lines(scope, d.path)
        violation_on_changed_lines(d, changed) || continue
        push!(out, d)
    end
    return out
end
