include("mutation_lib.jl")

const _DETECT = _MUTATION_VERIFY_DETECTED_EXIT

run_source_mutation(;
    name = "origin_label maps two members to same label",
    rel_path = "src/types.jl",
    needle = "    elseif o == Origin.PROJECT\n        return \"[Project]\"",
    replacement = "    elseif o == Origin.PROJECT\n        return \"[Preset]\"",
    verify = root -> begin
        script = """
        using AgentRuleLint
        labs = AgentRuleLint.origin_label.(instances(AgentRuleLint.Origin.T))
        length(unique(labs)) == length(labs) || exit($_DETECT)
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
