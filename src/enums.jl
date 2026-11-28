using EnumX

@enumx Level FORBID DENY WARN ALLOW

@enumx Origin AGENTRULELINT PRESET PROJECT

@enumx OutputFormat HUMAN JSON AGENT

function wire_name(x::Level.T)::String
    return lowercase(String(Symbol(x)))
end

function wire_name(x::Origin.T)::String
    return lowercase(String(Symbol(x)))
end

function wire_name(x::OutputFormat.T)::String
    return lowercase(String(Symbol(x)))
end

function parse_enum(::Type{Level.T}, s::AbstractString)::Level.T
    key = lowercase(strip(String(s)))
    for x in instances(Level.T)
        wire_name(x) == key && return x
    end
    valid = join(wire_name.(instances(Level.T)), "|")
    throw(ConfigError("unknown level '$s' (expected $valid)"))
end

function parse_enum(::Type{OutputFormat.T}, s::AbstractString)::OutputFormat.T
    key = lowercase(strip(String(s)))
    for x in instances(OutputFormat.T)
        wire_name(x) == key && return x
    end
    valid = join(wire_name.(instances(OutputFormat.T)), "|")
    throw(ConfigError("unknown format '$s' (expected $valid)"))
end
