# Exit contract: 0 = detector alive, 2 = disabled (do not use 1; harness treats 1 as crash).

using AgentRuleLint

const run_git_cmd = AgentRuleLint.run_git_cmd

include(joinpath(@__DIR__, "..", "..", "github_actions_log.jl"))
include(joinpath(@__DIR__, "..", "run_all_lib.jl"))

function main()
    return AgentRuleLint.git_run_scope() do
        return _github_actions_log_groups_detector_body()
    end
end

function _github_actions_log_groups_detector_body()
    dir = mktempdir()
    return try
        write(joinpath(dir, "trivial_pass.jl"), "exit(0)\n")
        buf = IOBuffer()
        out_path = tempname()
        withenv("GITHUB_ACTIONS" => "true") do
            open(out_path, "w") do io
                redirect_stdout(io) do
                    code = mutation_run_all_main(dir)
                    code == 0 || error("mutation_run_all_main exited $code")
                end
            end
        end
        out = read(out_path, String)
        rm(out_path, force = true)
        ng = count("::group::", out)
        ne = count("::endgroup::", out)
        alive = ng == ne && ng >= 1 && occursin("::group::trivial_pass.jl", out)
        exit(alive ? 0 : 2)
    finally
        rm(dir, recursive = true, force = true)
    end
end

exit(main())
