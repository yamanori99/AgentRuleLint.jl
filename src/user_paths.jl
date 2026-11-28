# User-supplied path validation (fail-closed; input boundary only).

function _lint_path_matched(norm::AbstractString, rel_files::Vector{String})
    for rel in rel_files
        rel == norm && return true
        startswith(rel, norm * "/") && return true
    end
    return false
end

"""
    validate_user_lint_paths!(root, given_paths, rel_files)

Every explicit lint path must match at least one scanned file after `normalize_path`.
"""
function validate_user_lint_paths!(root::AbstractString, given_paths::Vector{String}, rel_files::Vector{String})
    isempty(given_paths) && return nothing
    root = abspath(String(root))
    for given in given_paths
        norm = normalize_path(given)
        _lint_path_matched(norm, rel_files) && continue
        ap = isabspath(norm) ? norm : joinpath(root, norm)
        isfile(ap) && continue
        throw(ConfigError("path matched no files: given=$(repr(given)) normalized=$(repr(norm))"))
    end
    return nothing
end

function resolve_user_config_path(root::AbstractString, config_path)
    if config_path === nothing
        return (nothing, joinpath(abspath(String(root)), CONFIG_FILENAME))
    end
    given = String(config_path)
    norm = normalize_path(given)
    resolved = isabspath(norm) ? norm : joinpath(abspath(String(root)), norm)
    return (given, resolved)
end
