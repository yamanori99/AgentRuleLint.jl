function filter_interrupt_then_throw(err)
    return try
        risky()
    catch err
        err isa InterruptException && rethrow()
        throw(ArgumentError(string(err)))
    end
end
