module BoundarySafe
function ok()
    ccall(:getpid, Cint, ())
    return nothing
end
end
