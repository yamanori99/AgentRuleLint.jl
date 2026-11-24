function filter_isa_or(e)
    return try
        risky()
    catch e
        e isa ErrorException || rethrow()
    end
end
