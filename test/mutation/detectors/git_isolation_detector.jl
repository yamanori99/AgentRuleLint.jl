#!/usr/bin/env julia
# Detector: check --diff must ignore hostile global git config (exit 0 = alive, 2 = disabled).

using AgentRuleLint

include(joinpath(@__DIR__, "..", "..", "git_test_helpers.jl"))

const _HITS_EXIT = 42

function main()
    hostile = mktempdir()
    dir = mktempdir()
    return try
        open(joinpath(hostile, ".gitconfig"), "w") do io
            println(io, "[diff]")
            println(io, "\trenames = false")
        end
        init_git_repo!(dir)
        cfg = joinpath(dir, ".AgentRuleLint.jl.toml")
        write(cfg, "default_format = \"human\"\n")
        write(joinpath(dir, "x.jl"), "1\n")
        git_commit_all!(dir, "base")
        write(joinpath(dir, "y.jl"), "2\n")
        git_commit_all!(dir, "head")
        out_clean = withenv("HOME" => mktempdir()) do
            sprint() do io
                redirect_stdout(io) do
                    check(dir; diff_base = "HEAD^1")
                end
            end
        end
        out_hostile = withenv("HOME" => hostile) do
            sprint() do io
                redirect_stdout(io) do
                    check(dir; diff_base = "HEAD^1")
                end
            end
        end
        out_clean == out_hostile && exit(0)
        exit(_HITS_EXIT)
    catch err
        err isa InterruptException && rethrow()
        showerror(stderr, err)
        exit(1)
    finally
        rm(hostile, recursive = true, force = true)
        rm(dir, recursive = true, force = true)
    end
end

main()
