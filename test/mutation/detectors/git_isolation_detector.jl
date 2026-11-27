#!/usr/bin/env julia
# Detector: check --diff must ignore hostile global git config (exit 0 = alive, 42 = disabled).

using AgentRuleLint

include(joinpath(@__DIR__, "..", "..", "git_test_helpers.jl"))

const _HITS_EXIT = 42
const _DIFF_ISOLATION_BASE = GIT_ISOLATION_DIFF_BASE

function compare_signatures(hostile_home::String)
    dir = mktempdir()
    try
        hostile_renames_global_gitconfig!(hostile_home)
        rename_diff_literal_isolation_fixture(dir)
        clean = git_check_isolation_signature(dir, _DIFF_ISOLATION_BASE, mktempdir())
        hostile = git_check_isolation_signature(dir, _DIFF_ISOLATION_BASE, hostile_home)
        return clean == hostile
    finally
        rm(dir, recursive = true, force = true)
    end
end

function main()
    return AgentRuleLint.git_run_scope() do
        hostile = mktempdir()
        try
            compare_signatures(hostile) || exit(_HITS_EXIT)
            exit(0)
        catch err
            err isa InterruptException && rethrow()
            rethrow()
        finally
            rm(hostile, recursive = true, force = true)
        end
    end
end

main()
