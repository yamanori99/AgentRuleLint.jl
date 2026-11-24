# Negative: macro name contains "assume_effects" as substring but is not the macro.
macro not_assume_effects(x)
    return x
end

function fine()
    @not_assume_effects 1
    return nothing
end
