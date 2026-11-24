const PARSER_TREE = JuliaSyntax.GreenNode

function parse_source(text::AbstractString; syntax_version = VERSION, filename = nothing)
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
        if err isa JuliaSyntax.ParseError
            label = filename === nothing ? "source" : string(filename)
            throw(ParseError("syntax error in $label: $(err)"))
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
