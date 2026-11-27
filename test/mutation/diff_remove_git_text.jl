include("mutation_lib.jl")

const _DIFF_HARDENING_DETECTOR = "test/mutation/detectors/diff_hardening_detector.jl"

assert_detector_alive(_julia_project_cmd(MUTATION_ROOT, _DIFF_HARDENING_DETECTOR))

run_source_mutation(;
    name = "git diff --text removal",
    rel_path = "src/diff.jl",
    needle = "\"--text\",",
    replacement = "",
    replace_count = typemax(Int),
    # When `--text` is dropped on `-diff` paths, fail-closed binary handling still blocks
    # silent misses unless the probe-binary guard is weakened (detector then exits 2).
    extra_patches = [
        "text && push!(args, \"--text\")" => "false",
        """throw(GitError("git diff numstat probe binary for path=\$(path) (fail closed)"))""" =>
            "return lines",
    ],
    verify = root -> begin
        cmd = _julia_project_cmd(root, _DIFF_HARDENING_DETECTOR)
        return detector_disabled(cmd; dir = root)
    end,
)
