include("mutation_lib.jl")
using AgentRuleLint

const _DETECT = _MUTATION_VERIFY_DETECTED_EXIT

run_source_mutation(;
    name = "config legacy filename fallback",
    rel_path = "src/config.jl",
    needle = join(
        ["    reject_legacy_config_file!(root)", "    cfg = something(config_path, joinpath(abspath(root), CONFIG_FILENAME))"],
        '\n',
    ),
    replacement = """    cfg = something(config_path, begin
        p = joinpath(abspath(root), CONFIG_FILENAME)
        isfile(p) ? p : joinpath(abspath(root), LEGACY_CONFIG_FILENAME)
    end)""",
    verify = root -> begin
        legacy = repr(AgentRuleLint.LEGACY_CONFIG_FILENAME)
        script = """
        using AgentRuleLint
        tmp = mktempdir()
        try
            write(joinpath(tmp, $legacy), "agentrulelint_version = \\\"=0.1.0\\\"\\n")
            try
                AgentRuleLint.check(tmp)
                exit($_DETECT)
            catch err
                err isa AgentRuleLint.ConfigError || rethrow(err)
                exit(0)
            end
        finally
            rm(tmp, recursive=true, force=true)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
