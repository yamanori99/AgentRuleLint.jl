function _emit_fail_closed(err)
    return err === nothing ? 0 : 1
end

function swallow_fake_emit(err)
    return try
        risky()
    catch err
        return _emit_fail_closed(err)
    end
end
