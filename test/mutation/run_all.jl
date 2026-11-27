# Entry point for standalone mutation harnesses under `test/mutation/`.
# Discover `*.jl` via glob (except `mutation_lib.jl` / this file); run each in a
# fresh Julia process. Exit non-zero if any mutation survives, a harness crashes,
# zero files are found, or real `src/` is dirty afterwards.

include(joinpath(@__DIR__, "run_all_lib.jl"))
exit(mutation_run_all_main())
