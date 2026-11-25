function with_default(p)
    function f(x = unsafe_load(p))
        return x
    end
    return f
end
