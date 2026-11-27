@testset "shared head parse tree (one parse_source per .jl)" begin
    corpus = joinpath("test", "corpus")
    jl_files = String[]
    for (dir, _, files) in walkdir(joinpath(ROOT, corpus))
        for f in files
            endswith(lowercase(f), ".jl") || continue
            rel = replace(relpath(joinpath(dir, f), ROOT), '\\' => '/')
            push!(jl_files, rel)
        end
    end
    sort!(jl_files)
    @test !isempty(jl_files)

    counts = Dict{String, Int}()
    unnamed = Ref(0)
    observer = function (meta)
        fn = meta.filename
        if fn === nothing
            unnamed[] += 1
            return
        end
        key = replace(String(fn), '\\' => '/')
        counts[key] = get(counts, key, 0) + 1
        return
    end

    AgentRuleLint.with_parse_source_observer(observer) do
        AgentRuleLint.check(ROOT; paths = [corpus])
    end

    @test unnamed[] == 0
    for rel in jl_files
        n = get(counts, rel, 0)
        @test n == 1
    end
    extras = setdiff(keys(counts), Set(jl_files))
    @test isempty(extras)
end

@testset "shared head parse tree with unsafe-boundary/strict preset" begin
    counts = Dict{String, Int}()
    unnamed = Ref(0)
    observer = function (meta)
        fn = meta.filename
        if fn === nothing
            unnamed[] += 1
            return
        end
        key = replace(String(fn), '\\' => '/')
        counts[key] = get(counts, key, 0) + 1
        return
    end
    corpus = joinpath("test", "corpus")
    AgentRuleLint.with_parse_source_observer(observer) do
        AgentRuleLint.check(ROOT; paths = [corpus])
    end
    @test unnamed[] == 0
    for (rel, n) in counts
        endswith(lowercase(rel), ".jl") || continue
        @test n == 1
    end
end
