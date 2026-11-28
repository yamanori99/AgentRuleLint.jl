include("mutation_lib.jl")

const _DETECT = _MUTATION_VERIFY_DETECTED_EXIT

run_source_mutation(;
    name = "human gutter excerpt cap",
    rel_path = "src/format/common.jl",
    needle = "excerpt, omit_suffix, _ = _human_gutter_excerpt(line)",
    replacement = "excerpt, omit_suffix, _ = line, \"\", 0",
    verify = root -> begin
        script = """
        using AgentRuleLint
        root = normpath(joinpath(dirname(pathof(AgentRuleLint)), ".."))
        path = joinpath("test", "corpus", "test_integrity_fold_budget.jl")
        res = AgentRuleLint.check(root; paths = [path])
        io = IOContext(IOBuffer(), :color => false)
        out = AgentRuleLint.format_human(res; root = root, io = io)
        for line in split(out, '\\n'; keepempty = false)
            occursin("> ", line) || continue
            length(line) > 1000 ? exit($_DETECT) : exit(0)
        end
        exit(0)
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
