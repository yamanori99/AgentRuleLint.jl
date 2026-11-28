include("mutation_lib.jl")

const _DETECT = _MUTATION_VERIFY_DETECTED_EXIT

run_source_mutation(;
    name = "parse_enum OutputFormat accepts unknown strings",
    rel_path = "src/enums.jl",
    needle = join(
        [
            "    valid = join(wire_name.(instances(OutputFormat.T)), \"|\")",
            "    throw(ConfigError(\"unknown format '\$s' (expected \$valid)\"))",
        ],
        "\n",
    ),
    replacement = "    return OutputFormat.JSON",
    verify = root -> begin
        script = """
        using AgentRuleLint
        try
            AgentRuleLint.parse_enum(AgentRuleLint.OutputFormat.T, "not-a-format")
            exit($_DETECT)
        catch err
            err isa AgentRuleLint.ConfigError || rethrow(err)
            exit(0)
        end
        """
        return mutation_verify_script(root, script; dir = root)
    end,
)
