# Corpus slice: project rule (repo config) + shell-safety preset (minimal config only).
const REENTRANT_PATHS = [
    joinpath("test", "corpus", "expect_standalone.jl"),
    joinpath("test", "corpus", "shell_cmd_pkill.jl"),
]
const REENTRANT_ASYNC_TASKS = 4
const REENTRANT_MINIMAL_CFG = joinpath(
    ROOT,
    "test",
    "goldens",
    "output",
    "minimal_config",
    ".AgentRuleLint.jl.toml",
)
const REENTRANT_SPAWN_WORKER = joinpath(@__DIR__, "check_reentrant_spawn_worker.jl")

function _reentrant_seed_corpus!(tmp::AbstractString)
    dst = joinpath(tmp, "test", "corpus")
    mkpath(dst)
    for rel in REENTRANT_PATHS
        src = joinpath(ROOT, rel)
        cp(src, joinpath(dst, basename(rel)); force = true)
    end
    return nothing
end

function _reentrant_temp_root(; config_path::Union{Nothing, AbstractString} = nothing)
    tmp = mktempdir()
    _reentrant_seed_corpus!(tmp)
    if config_path !== nothing
        cp(config_path, joinpath(tmp, ".AgentRuleLint.jl.toml"); force = true)
    end
    return tmp
end

function _reentrant_spawn_worker_cmd(check_roots::Vector{String})
    return Cmd(
        vcat(
            collect(Base.julia_cmd()),
            [
                "--startup-file=no",
                "--project=$(ROOT)",
                "--threads=4",
                "--compiled-modules=existing",
                REENTRANT_SPAWN_WORKER,
                string(length(REENTRANT_PATHS)),
                REENTRANT_PATHS...,
                String.(check_roots)...,
            ],
        ),
    )
end

function _assert_spawn_worker_roots(check_roots::Vector{String})
    length(check_roots) >= 2 ||
        error("spawn worker needs ≥2 roots (repo, no config, minimal)")
    isfile(REENTRANT_SPAWN_WORKER) ||
        error("missing spawn worker script: $REENTRANT_SPAWN_WORKER")
    cmd = _reentrant_spawn_worker_cmd(check_roots)
    proc = run(ignorestatus(cmd))
    proc.exitcode == 0 ||
        error("spawn parallel child failed (exit $(proc.exitcode)): $cmd")
    return true
end

function _assert_async_parallel(seq::AgentRuleLint.CheckResult, root::AbstractString)
    nt = (; paths = REENTRANT_PATHS)
    n = REENTRANT_ASYNC_TASKS
    tasks = Vector{Task}(undef, n)
    for i in 1:n
        tasks[i] = @async AgentRuleLint.check(root; nt...)
    end
    for t in tasks
        @test fetch(t) == seq
    end
    return nothing
end

@testset "check reentrant (concurrent)" begin
    spawn_roots = String[]

    @testset "repo config" begin
        seq = AgentRuleLint.check(ROOT; paths = REENTRANT_PATHS)
        push!(spawn_roots, ROOT)
        _assert_async_parallel(seq, ROOT)
    end

    @testset "no config file" begin
        tmp = _reentrant_temp_root()
        try
            @test !isfile(joinpath(tmp, ".AgentRuleLint.jl.toml"))
            seq = AgentRuleLint.check(tmp; paths = REENTRANT_PATHS)
            push!(spawn_roots, tmp)
            _assert_async_parallel(seq, tmp)
        finally
            rm(tmp; recursive = true, force = true)
        end
    end

    @testset "minimal config" begin
        tmp = _reentrant_temp_root(config_path = REENTRANT_MINIMAL_CFG)
        try
            seq = AgentRuleLint.check(tmp; paths = REENTRANT_PATHS)
            push!(spawn_roots, tmp)
            _assert_async_parallel(seq, tmp)
        finally
            rm(tmp; recursive = true, force = true)
        end
    end

    @test _assert_spawn_worker_roots(spawn_roots)
end
