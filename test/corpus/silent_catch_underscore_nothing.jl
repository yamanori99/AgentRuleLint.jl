function swallow_underscore()
    return try
        risky()
    catch _e
        nothing
    end
end
