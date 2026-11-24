function evade(x)
    ex = Expr(:call, :eval, x)
    return ex
end
