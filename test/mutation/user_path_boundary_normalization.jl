include("mutation_lib.jl")
using AgentRuleLint

const _DETECT = _MUTATION_VERIFY_DETECTED_EXIT

run_source_mutation(;
    name = "user path input normalization",
    rel_path = "src/path_glob.jl",
    needle = "    s = replace(String(p), '\\\\' => '/')",
    replacement = "    s = String(p)",
    verify = root -> begin
        script = """
        using AgentRuleLint
        root = normpath(joinpath(dirname(pathof(AgentRuleLint)), ".."))
        try
            _, ctxs = AgentRuleLint.run_check_pipeline(root; paths = ["src\\\\AgentRuleLint.jl"])
            isempty(ctxs) ? exit($_DETECT) : exit(0)
        catch err
            err isa AgentRuleLint.ConfigError && occursin("path matched no files", err.msg) ? exit($_DETECT) : rethrow(err)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
