using EnumX

@enumx Level FORBID DENY WARN ALLOW

@enumx Origin AGENTRULELINT PRESET PROJECT

function wire_name(x::Level.T)::String
    return lowercase(String(Symbol(x)))
end

function wire_name(x::Origin.T)::String
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
