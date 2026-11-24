const E = Core.eval

function evade_via_alias(x)
    return E(x)
end

function evade_interp(x)
    return @eval $(esc(x))
end
