include("mutation_lib.jl")

const _DIFF_HARDENING_DETECTOR = "test/mutation/detectors/diff_hardening_detector.jl"

assert_detector_alive(_julia_project_cmd(MUTATION_ROOT, _DIFF_HARDENING_DETECTOR))

run_source_mutation(;
    name = "git diff --text removal",
    rel_path = "src/diff.jl",
    needle = "\"--text\",",
    replacement = "",
    replace_count = typemax(Int),
    verify = root -> begin
        cmd = _julia_project_cmd(root, _DIFF_HARDENING_DETECTOR)
        proc = run(ignorestatus(setenv(cmd; dir = root)))
        proc.exitcode == 0 ||
            error("patched tree must keep detector alive (exit 0), got $(proc.exitcode)")
        return true
    end,
)
