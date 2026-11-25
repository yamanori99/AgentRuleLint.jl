function demo_qualified()
    Base.invokelatest(println, "hi")
    Base.Meta.parse("1+1")
    Core.Meta.parse("x")
    return Base.unsafe_load(C_NULL)
end
