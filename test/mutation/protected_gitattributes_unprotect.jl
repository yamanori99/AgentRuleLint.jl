include("mutation_lib.jl")

const _PROT_GITATTR_DETECTOR = "test/mutation/detectors/protected_gitattributes_detector.jl"

assert_detector_alive(_julia_project_cmd(MUTATION_ROOT, _PROT_GITATTR_DETECTOR))

run_source_mutation(;
    name = "unprotect .gitattributes",
    rel_path = "src/rules/protected_paths.jl",
    needle = """
        ".gitattributes",
    """,
    replacement = "",
    verify = root -> begin
        cmd = _julia_project_cmd(root, _PROT_GITATTR_DETECTOR)
        return detector_disabled(cmd; dir = root)
    end,
)
