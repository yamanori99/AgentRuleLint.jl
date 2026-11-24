function filter_isa_call_or(err)
    return try
        risky()
    catch err
        isa(err, ErrorException) || rethrow()
    end
end
