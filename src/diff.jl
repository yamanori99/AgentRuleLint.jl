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

"""Single path from `git diff --name-status` (rename records both `path` and `old_path`)."""
struct DiffPathEvent
    status::Char
    path::String
    old_path::String
end

function _git_root(path::AbstractString)
    root = abspath(String(path))
    isdir(root) || throw(GitError("not a directory: $root"))
    try
        out = strip(
            String(
                read(Cmd(["git", "-C", root, "rev-parse", "--show-toplevel"])),
            ),
        )
        return out
    catch err
        err isa InterruptException && rethrow()
        throw(GitError("not a git repository: $root"))
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
    try
        strip(String(read(cmd)))
        return ref
    catch err
        err isa InterruptException && rethrow()
        if ref == DEFAULT_DIFF_BASE
            throw(GitError("diff base ref not available: HEAD^1 (shallow clone or single-parent HEAD)"))
        end
        throw(GitError("diff base ref not available: $ref"))
    end
end

function resolve_diff_base_arg(raw)
    raw === nothing && return nothing
    return strip(String(raw))
end

function git_diff_name_status(root::AbstractString, base::AbstractString)
    root = _git_root(root)
    base = verify_diff_base_ref(root, base)
    cmd = Cmd(
        [
            "git",
            "-C",
            root,
            "diff",
            "-z",
            "--no-ext-diff",
            "--no-textconv",
            "--name-status",
            "--end-of-options",
            base,
        ],
    )
    bytes = try
        read(cmd)
    catch err
        err isa InterruptException && rethrow()
        throw(GitError("git diff failed for base=$(base)"))
    end
    isempty(bytes) && return Tuple{Char, String}[]
    return _parse_diff_name_status(String(bytes))
end

function _parse_diff_name_status(payload::AbstractString)
    parts = split(String(payload), '\0'; keepempty = false)
    out = Tuple{Char, String}[]
    i = 1
    while i <= length(parts)
        status = parts[i]
        i += 1
        if status[1] == 'R' && i + 1 <= length(parts)
            i += 1
            path = parts[i]
            i += 1
        elseif status[1] in ('A', 'M', 'D', 'C', 'T') && i <= length(parts)
            path = parts[i]
            i += 1
        else
            continue
        end
        push!(out, (status[1], normalize_path(path)))
    end
    return unique(out)
end

function git_diff_path_events(root::AbstractString, base::AbstractString)
    root = _git_root(root)
    base = verify_diff_base_ref(root, base)
    cmd = Cmd(
        [
            "git",
            "-C",
            root,
            "diff",
            "-z",
            "--no-ext-diff",
            "--no-textconv",
            "--name-status",
            "--end-of-options",
            base,
        ],
    )
    bytes = try
        read(cmd)
    catch err
        err isa InterruptException && rethrow()
        throw(GitError("git diff failed for base=$(base)"))
    end
    isempty(bytes) && return DiffPathEvent[]
    return _parse_diff_path_events(String(bytes))
end

function _parse_diff_path_events(payload::AbstractString)
    parts = split(String(payload), '\0'; keepempty = false)
    out = DiffPathEvent[]
    i = 1
    while i <= length(parts)
        status = parts[i]
        i += 1
        if status[1] == 'R' && i + 1 <= length(parts)
            oldp = normalize_path(parts[i])
            newp = normalize_path(parts[i + 1])
            i += 2
            push!(out, DiffPathEvent('R', newp, oldp))
        elseif status[1] in ('A', 'M', 'D', 'C', 'T') && i <= length(parts)
            path = normalize_path(parts[i])
            i += 1
            push!(out, DiffPathEvent(status[1], path, ""))
        else
            continue
        end
    end
    return out
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

function git_diff_changed_lines(root::AbstractString, base::AbstractString, relpath::AbstractString)
    root = _git_root(root)
    base = verify_diff_base_ref(root, base)
    path = normalize_path(relpath)
    cmd = Cmd(
        [
            "git",
            "-C",
            root,
            "diff",
            "-U0",
            "--no-color",
            "--no-ext-diff",
            "--no-textconv",
            "--end-of-options",
            base,
            "--",
            path,
        ],
    )
    bytes = try
        read(cmd)
    catch err
        err isa InterruptException && rethrow()
        throw(GitError("git diff failed for base=$(base) path=$(path)"))
    end
    return _parse_unified_hunks(String(bytes))
end

function build_diff_scope(root::AbstractString, base::AbstractString)
    root = _git_root(root)
    base = verify_diff_base_ref(root, base)
    entries = git_diff_name_status(root, base)
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
            git_diff_changed_lines(root, base, path)
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

function filter_diff_violations!(diags::Vector{Violation}, scope::DiffScope)
    out = Violation[]
    for d in diags
        st = diff_path_status(scope, d.path)
        st == 'D' && continue
        changed = diff_changed_lines(scope, d.path)
        violation_on_changed_lines(d, changed) || continue
        push!(out, d)
    end
    return out
end
