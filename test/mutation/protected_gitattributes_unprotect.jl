include("mutation_lib.jl")

run_source_mutation(;
    name = "unprotect .gitattributes",
    rel_path = "src/rules/protected_paths.jl",
    needle = """
        ".gitattributes",
    """,
    replacement = "",
    verify = root -> begin
        cmd = _julia_project_cmd(root, "test/mutation/protected_gitattributes_detector.jl")
        return detector_disabled(cmd; dir = root)
    end,
)