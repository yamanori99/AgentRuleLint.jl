include("mutation_lib.jl")

const _GIT_ISOLATION_DETECTOR = joinpath(@__DIR__, "detectors", "git_isolation_detector.jl")

assert_detector_alive(_julia_project_cmd(MUTATION_ROOT, _GIT_ISOLATION_DETECTOR))

run_source_mutation(;
    name = "git config isolation env removed",
    rel_path = "src/git.jl",
    needle = raw"""function git_cmd(root::AbstractString, args::AbstractString...)
        g = _git_executable_cmd(root)
        tail = Cmd(vcat(_git_cmd_argv_prefix(root), collect(String, args)))
        return setenv(`$g $tail`, _git_merged_env())
    end""",
    replacement = raw"""function git_cmd(root::AbstractString, args::AbstractString...)
        r = abspath(String(root))
        g = _git_executable_cmd(root)
        tail = Cmd(vcat(String["-C", r, "-c", "safe.directory=$(r)"], collect(String, args)))
        return `$g $tail`
    end""",
    replace_count = 1,
    verify = root -> begin
        cmd = _julia_project_cmd(root, _GIT_ISOLATION_DETECTOR)
        return mutation_verify_detected(cmd; dir = root)
    end,
)
