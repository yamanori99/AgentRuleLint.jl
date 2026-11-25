function demo_assume()
    @assume_effects :foldable foo()
    Base.@assume_effects :foldable bar()
    return nothing
end
