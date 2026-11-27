const OUTPUT_GOLDEN_VERSION_PLACEHOLDER = "<VERSION>"
const OUTPUT_GOLDEN_GIT_EXECUTABLE_PLACEHOLDER = "<GIT>"
const OUTPUT_GOLDEN_GIT_VERSION_PLACEHOLDER = "<GIT_VERSION>"

function _golden_substitute_runtime(
        text::AbstractString;
        git_executable::AbstractString = "",
        git_version::AbstractString = "",
    )
    t = String(text)
    ver = string(AgentRuleLint.AGENTRULELINT_VERSION)
    t = replace(t, ver => OUTPUT_GOLDEN_VERSION_PLACEHOLDER)
    !isempty(git_executable) &&
        (t = replace(t, git_executable => OUTPUT_GOLDEN_GIT_EXECUTABLE_PLACEHOLDER))
    !isempty(git_version) &&
        (t = replace(t, git_version => OUTPUT_GOLDEN_GIT_VERSION_PLACEHOLDER))
    return t
end

function _golden_normalize_text(
        text::AbstractString;
        git_executable::AbstractString = "",
        git_version::AbstractString = "",
    )
    stripped = AgentRuleLint.strip_ansi(text)
    return _golden_substitute_runtime(stripped; git_executable, git_version)
end

"""Drop the JSONL header object (`"type":"header"`)."""
function _golden_json_without_header(text::AbstractString)
    lines = split(text, '\n'; keepempty = true)
    kept = String[]
    for line in lines
        isempty(line) && (push!(kept, line); continue)
        if occursin("\"type\":\"header\"", line) || occursin("\"type\": \"header\"", line)
            continue
        end
        push!(kept, line)
    end
    return join(kept, '\n')
end
