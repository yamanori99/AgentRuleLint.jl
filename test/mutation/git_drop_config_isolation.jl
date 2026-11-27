include("mutation_lib.jl")

const _GIT_ISOLATION_DETECTOR = joinpath(@__DIR__, "detectors", "git_isolation_detector.jl")

assert_detector_alive(_julia_project_cmd(MUTATION_ROOT, _GIT_ISOLATION_DETECTOR))

run_source_mutation(;
    name = "git config isolation env removed",
    rel_path = "src/git.jl",
    needle = raw"return addenv(`$g $tail`, _git_isolated_env()...)",
    replacement = raw"return `$g $tail`",
    replace_count = 1,
    verify = root -> begin
        diff_path = joinpath(root, "src", "diff.jl")
        text = read(diff_path, String)
        patched = replace(text, "        \"-c\",\n        \"diff.renames=true\",\n" => "")
        patched = replace(patched, "        \"-M\",\n" => "")
        patched != text && write(diff_path, patched)
        cmd = _julia_project_cmd(root, _GIT_ISOLATION_DETECTOR)
        return mutation_verify_detected(cmd; dir = root)
    end,
)
