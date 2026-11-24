const E = Core.eval

function via_alias(x)
    return E(x)
end

function via_assign()
    f = invokelatest
    return f
end

function via_higher_order(xs)
    return map(eval, xs)
end
