#!/usr/bin/env julia
# Detector: check --diff must ignore hostile global git config (exit 0 = alive, 42 = disabled).

using AgentRuleLint

include(joinpath(@__DIR__, "..", "..", "git_test_helpers.jl"))

const _HITS_EXIT = 42

function compare_signatures(hostile_home::String)
    dir = mktempdir()
    try
        rename_diff_literal_isolation_fixture(dir)
        clean = withenv("HOME" => mktempdir()) do
            active_violation_paths(AgentRuleLint.check(dir; diff_base = "HEAD^1"))
        end
        hostile = withenv("HOME" => hostile_home) do
            active_violation_paths(AgentRuleLint.check(dir; diff_base = "HEAD^1"))
        end
        return clean == hostile
    finally
        rm(dir, recursive = true, force = true)
    end
end

function main()
    return AgentRuleLint.git_run_scope() do
        hostile = mktempdir()
        return try
            write(
                joinpath(hostile, ".gitconfig"),
                "[diff]\n\trenames = false\n",
            )
            compare_signatures(hostile) && exit(0)
            exit(_HITS_EXIT)
        catch err
            err isa InterruptException && rethrow()
            showerror(stderr, err)
            exit(1)
        finally
            rm(hostile, recursive = true, force = true)
        end
    end
end

main()
