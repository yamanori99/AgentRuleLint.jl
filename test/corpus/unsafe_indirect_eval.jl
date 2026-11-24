function demo_indirect()
    f = getfield(Base, :eval)
    return f(:x)
end
