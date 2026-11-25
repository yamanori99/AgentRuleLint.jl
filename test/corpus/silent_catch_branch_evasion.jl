function swallow_partial_branch(e)
    return try
        risky()
    catch e
        if e isa ErrorException
            rethrow()
        end
    end
end
