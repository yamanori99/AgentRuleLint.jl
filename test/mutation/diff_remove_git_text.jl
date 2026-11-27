include("mutation_lib.jl")

run_source_mutation(;
    name = "git diff --text removal",
    rel_path = "src/diff.jl",
    needle = "\"--text\",",
    replacement = "",
    replace_count = typemax(Int),
    verify = root -> begin
        cmd = _julia_project_cmd(root, "test/mutation/diff_hardening_detector.jl")
        proc = run(ignorestatus(setenv(cmd; dir = root)))
        return proc.exitcode == 0
    end,
)
