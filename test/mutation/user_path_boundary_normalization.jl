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
        tmp = mktempdir()
        try
            mkpath(joinpath(tmp, "src"))
            write(joinpath(tmp, "src", "hit.jl"), "x = 1\\n")
            ver = string(pkgversion(AgentRuleLint))
            write(
                joinpath(tmp, ".AgentRuleLint.jl.toml"),
                "agentrulelint_version = \\\"=$(ver)\\\"\\n",
            )
            _, ctxs = AgentRuleLint.run_check_pipeline(tmp; paths = ["src\\\\\\\\hit.jl"])
            isempty(ctxs) ? exit($_DETECT) : exit(0)
        finally
            rm(tmp, recursive=true, force=true)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)