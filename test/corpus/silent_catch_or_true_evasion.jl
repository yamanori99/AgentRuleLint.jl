function swallow_or_true()
    return try
        risky()
    catch e
        true || rethrow()
    end
end
