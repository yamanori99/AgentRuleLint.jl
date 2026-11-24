function swallow_dead_rethrow()
    return try
        risky()
    catch e
        return 0
        rethrow()
    end
end
