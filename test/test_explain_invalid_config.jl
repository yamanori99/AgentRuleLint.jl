using AgentRuleLint

dir = abspath(mktempdir())
err_path = tempname()
try
    write(joinpath(dir, ".AgentRuleLintConfig.toml"), "agentrulelint_version = \"=99.99.99\"\n")
    code = cd(dir) do
        open(err_path, "w") do err_io
            redirect_stderr(err_io) do
                AgentRuleLint.cli_main(["explain", "test-integrity"])
            end
        end
    end
    err = isfile(err_path) ? read(err_path, String) : ""
    ok =
        code == 2 &&
        occursin("99.99.99", err) &&
        occursin("agentrulelint_version", err) &&
        !occursin("unknown rule id", err)
    # 42 = mutation detected (see `_MUTATION_VERIFY_DETECTED_EXIT` in test/mutation/mutation_lib.jl)
    exit(ok ? 0 : 42)
finally
    isfile(err_path) && rm(err_path; force = true)
    rm(dir, recursive = true, force = true)
end
