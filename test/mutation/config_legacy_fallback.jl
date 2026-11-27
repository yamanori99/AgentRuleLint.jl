include("mutation_lib.jl")

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
        tmp = mktempdir()
        try
            write(
                joinpath(tmp, AgentRuleLint.LEGACY_CONFIG_FILENAME),
                "agentrulelint_version = \"=0.1.0\"\n",
            )
            survived = try
                AgentRuleLint.check(tmp)
                true
            catch
                false
            end
            return !survived
        finally
            rm(tmp, recursive = true, force = true)
        end
    end,
)