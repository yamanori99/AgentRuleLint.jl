const REENTRANT_CORPUS = [joinpath("test", "corpus")]
const REENTRANT_PARALLEL = 4
const REENTRANT_MINIMAL_CFG = joinpath(
    ROOT,
    "test",
    "goldens",
    "output",
    "minimal_config",
    "AgentRuleLintConfig.toml",
)

function _reentrant_temp_root(; config_path::Union{Nothing, AbstractString} = nothing)
    tmp = mktempdir()
    mkpath(joinpath(tmp, "test"))
    cp(joinpath(ROOT, "test", "corpus"), joinpath(tmp, "test", "corpus"); force = true)
    if config_path !== nothing
        cp(config_path, joinpath(tmp, ".AgentRuleLintConfig.toml"); force = true)
    end
    return tmp
end

function _assert_same_check(seq::AgentRuleLint.CheckResult, root::AbstractString; kwargs...)
    nt = merge((; paths = REENTRANT_CORPUS), NamedTuple(kwargs))
    n = REENTRANT_PARALLEL

    for _ in 1:n
        t = Threads.@spawn AgentRuleLint.check(root; nt...)
        @test fetch(t) == seq
    end

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
    @testset "repo config" begin
        seq = AgentRuleLint.check(ROOT; paths = REENTRANT_CORPUS)
        _assert_same_check(seq, ROOT)
    end

    @testset "no config file" begin
        tmp = _reentrant_temp_root()
        try
            @test !isfile(joinpath(tmp, ".AgentRuleLintConfig.toml"))
            seq = AgentRuleLint.check(tmp; paths = REENTRANT_CORPUS)
            _assert_same_check(seq, tmp)
        finally
            rm(tmp; recursive = true, force = true)
        end
    end

    @testset "minimal config" begin
        tmp = _reentrant_temp_root(config_path = REENTRANT_MINIMAL_CFG)
        try
            seq = AgentRuleLint.check(tmp; paths = REENTRANT_CORPUS)
            _assert_same_check(seq, tmp)
        finally
            rm(tmp; recursive = true, force = true)
        end
    end
end
