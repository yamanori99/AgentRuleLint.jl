function filter_if_else(e)
    return try
        risky()
    catch e
        if e isa ErrorException
            handle(e)
        else
            rethrow()
        end
    end
end
