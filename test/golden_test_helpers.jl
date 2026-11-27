const OUTPUT_GOLDEN_VERSION_PLACEHOLDER = "<VERSION>"

function _golden_substitute_version(text::AbstractString)
    ver = string(AgentRuleLint.AGENTRULELINT_VERSION)
    return replace(text, ver => OUTPUT_GOLDEN_VERSION_PLACEHOLDER)
end

function _golden_normalize_text(text::AbstractString)
    return _golden_substitute_version(AgentRuleLint.strip_ansi(text))
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
