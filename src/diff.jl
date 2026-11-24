function _git_root(path::AbstractString)
    root = abspath(String(path))
    isdir(root) || throw(GitError("not a directory: $root"))
    try
        out = strip(
            String(
                read(Cmd(["git", "-C", root, "rev-parse", "--show-toplevel", "--end-of-options"])),
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

function git_diff_name_status(root::AbstractString, base::AbstractString)
    root = _git_root(root)
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
    try
        bytes = read(cmd)
    catch err
        err isa InterruptException && rethrow()
        throw(GitError("git diff failed for base=$(base)"))
    end
    isempty(bytes) && return String[]
    parts = split(String(bytes), '\0'; keepempty = false)
    paths = String[]
    i = 1
    while i <= length(parts)
        status = parts[i]
        i += 1
        if status[1] == 'R' && i + 1 <= length(parts)
            i += 1
            path = parts[i]
            i += 1
        elseif status[1] in ('A', 'M', 'D', 'C') && i <= length(parts)
            path = parts[i]
            i += 1
        else
            continue
        end
        push!(paths, normalize_path(path))
    end
    return unique(paths)
end

function resolve_diff_paths(root::AbstractString; base = nothing, explicit_paths = String[])
    isempty(explicit_paths) || return normalize_path.(explicit_paths)
    base === nothing && return String[]
    return git_diff_name_status(root, base)
end
