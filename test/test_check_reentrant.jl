const REENTRANT_SAMPLE = joinpath("test", "corpus", "expect_standalone.jl")
const REENTRANT_PATHS = [REENTRANT_SAMPLE]
const REENTRANT_PARALLEL = 4
const REENTRANT_MINIMAL_CFG = joinpath(
    ROOT,
    "test",
    "goldens",
    "output",
    "minimal_config",
    "AgentRuleLintConfig.toml",
)
const REENTRANT_SPAWN_WORKER = joinpath(@__DIR__, "check_reentrant_spawn_worker.jl")

function _reentrant_seed_corpus!(tmp::AbstractString)
    dst = joinpath(tmp, "test", "corpus")
    mkpath(dst)
    src = joinpath(ROOT, REENTRANT_SAMPLE)
    cp(src, joinpath(dst, basename(REENTRANT_SAMPLE)); force = true)
    return nothing
end

function _reentrant_temp_root(; config_path::Union{Nothing, AbstractString} = nothing)
    tmp = mktempdir()
    _reentrant_seed_corpus!(tmp)
    if config_path !== nothing
        cp(config_path, joinpath(tmp, ".AgentRuleLintConfig.toml"); force = true)
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
                string(REENTRANT_PARALLEL),
                REENTRANT_SAMPLE,
                String.(check_roots)...,
            ],
        ),
    )
end

function _assert_spawn_worker_roots(check_roots::Vector{String})
    isempty(check_roots) && return true
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
    n = REENTRANT_PARALLEL
    async_results = Vector{AgentRuleLint.CheckResult}(undef, n)
    @sync for i in 1:n
        @async async_results[i] = AgentRuleLint.check(root; nt...)
    end
    for r in async_results
        @test r == seq
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
            @test !isfile(joinpath(tmp, ".AgentRuleLintConfig.toml"))
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
