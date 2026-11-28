include("mutation_lib.jl")

const _DETECT = _MUTATION_VERIFY_DETECTED_EXIT

run_source_mutation(;
    name = "parse_enum Level accepts unknown strings",
    rel_path = "src/enums.jl",
    needle = join(
        [
            "    valid = join(wire_name.(instances(Level.T)), \"|\")",
            "    throw(ConfigError(\"unknown level '\$s' (expected \$valid)\"))",
        ],
        "\n",
    ),
    replacement = "    return Level.DENY",
    verify = root -> begin
        script = """
        using AgentRuleLint
        try
            AgentRuleLint.parse_enum(AgentRuleLint.Level.T, "not-a-level")
            exit($_DETECT)
        catch err
            err isa AgentRuleLint.ConfigError || rethrow(err)
            exit(0)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
