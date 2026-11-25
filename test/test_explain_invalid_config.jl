using AgentRuleLint

dir = abspath(mktempdir())
try
    write(joinpath(dir, ".AgentRuleLintConfig.toml"), "agentrulelint_version = \"=99.99.99\"\n")
    code = cd(dir) do
        AgentRuleLint.cli_main(["explain", "test-integrity"])
    end
    exit(code == 2 ? 0 : 1)
finally
    rm(dir, recursive = true, force = true)
end
