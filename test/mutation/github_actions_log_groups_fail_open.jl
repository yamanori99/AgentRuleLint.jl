include("mutation_lib.jl")

const _GHA_LOG_GROUPS_DETECTOR = "test/mutation/detectors/github_actions_log_groups_detector.jl"

assert_detector_alive(_julia_project_cmd(MUTATION_ROOT, _GHA_LOG_GROUPS_DETECTOR))

run_source_mutation(;
    name = "disable GitHub Actions log groups",
    rel_path = "test/mutation/run_all_lib.jl",
    needle = """
            github_actions_group_begin(Base.stdout, r.name)
    """,
    replacement = "",
    verify = root -> begin
        cmd = _julia_project_cmd(root, _GHA_LOG_GROUPS_DETECTOR)
        return detector_disabled(cmd; dir = root)
    end,
)
