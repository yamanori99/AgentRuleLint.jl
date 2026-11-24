const PARSER_TREE = JuliaSyntax.GreenNode

function parse_source(text::AbstractString; syntax_version = VERSION, filename = nothing)
    return parseall(
        PARSER_TREE,
        text;
        version = syntax_version,
        filename = filename,
        ignore_errors = true,
        ignore_warnings = true,
    )
end

function parser_rev_string()
    return "JuliaSyntax@$(VERSION.major).$(VERSION.minor)"
end

function self_check_parser(text::AbstractString)
    tree = parse_source(text)
    meta_tree = Meta.parseall(text)
    return tree !== nothing && meta_tree !== nothing
end
