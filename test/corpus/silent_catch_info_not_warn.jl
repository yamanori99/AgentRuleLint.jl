function swallow_info_warn_string(err)
    return try
        risky()
    catch err
        @info "@warn" exception = err
    end
end
