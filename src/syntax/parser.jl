const PARSER_TREE = JuliaSyntax.GreenNode

# Test-only hook; default `nothing`. Scoped per `with_parse_source_observer` task.
const PARSE_SOURCE_OBSERVER = Base.ScopedValues.ScopedValue{Any}(nothing)

function with_parse_source_observer(f::Function, observer)
    return Base.ScopedValues.with(f, PARSE_SOURCE_OBSERVER => observer)
end

function parse_source(text::AbstractString; syntax_version = VERSION, filename = nothing)
    obs = PARSE_SOURCE_OBSERVER[]
    if obs !== nothing
        obs((; text = String(text), syntax_version = syntax_version, filename = filename))
    end
    try
        return parseall(
            PARSER_TREE,
            text;
            version = syntax_version,
            filename = filename,
            ignore_errors = false,
            ignore_warnings = true,
        )
    catch err
        err isa InterruptException && rethrow()
        if err isa JuliaSyntax.ParseError
            label = filename === nothing ? "source" : string(filename)
            throw(ParseError("syntax error in $label: $(format_error(err))"))
        end
        rethrow()
    end
end

function parser_rev_string()
    return "JuliaSyntax@$(VERSION.major).$(VERSION.minor)"
end

function self_check_parser(text::AbstractString)
    tree = parse_source(text)
    return tree !== nothing
end
