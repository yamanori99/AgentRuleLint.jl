function swallow_default()
    return try
        risky()
    catch e
        e = 0
    end
end
