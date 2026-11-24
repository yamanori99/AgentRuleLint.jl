function demo_ccall()
    ccall(:exit, Cvoid, (Cint,), 0)
    return nothing
end
