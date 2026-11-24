function evade_interp(x)
    return @eval $(esc(x))
end
