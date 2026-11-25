function swallow_nested()
    return try
        outer()
    catch e
        try
            inner(e)
        catch
            nothing
        end
    end
end
