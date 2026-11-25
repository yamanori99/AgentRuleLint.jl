# Named tolerance constants are a known test-integrity blind spot (documented in explain).
const LOOSE_ATOL = 1.0e-3
isapprox(1.0, 2.0; atol = LOOSE_ATOL)
