function demo_inbounds(A, i)
    @inbounds return A[i]
end
