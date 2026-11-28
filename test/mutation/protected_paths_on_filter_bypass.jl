include("mutation_lib.jl")

const _PROT_ON_FILTER_DETECTOR = "test/mutation/detectors/protected_paths_on_filter_detector.jl"

assert_detector_alive(_julia_project_cmd(MUTATION_ROOT, _PROT_ON_FILTER_DETECTOR))

run_source_mutation(;
    name = "bypass protected-paths on filter",
    rel_path = "src/rules/protected_paths.jl",
    needle = """
                word ∉ glob_entry.change_types && continue
    """,
    replacement = """
                continue
    """,
    verify = root -> begin
        cmd = _julia_project_cmd(root, _PROT_ON_FILTER_DETECTOR)
        return detector_disabled(cmd; dir = root)
    end,
)
