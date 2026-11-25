function swallow_log_only(err)
    return try
        risky()
    catch err
        @warn "ignored failure" exception = err
    end
end
