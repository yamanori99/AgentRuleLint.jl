function swallow_and_interrupt_only(e)
    return try
        risky()
    catch e
        e isa InterruptException && rethrow()
        return nothing
    end
end
