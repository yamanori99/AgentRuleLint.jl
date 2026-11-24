function swallow_empty()
    return try
        risky()
    catch e
    end
end
