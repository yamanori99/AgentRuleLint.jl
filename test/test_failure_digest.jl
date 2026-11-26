# Isolated DefaultTestSet probes: `@with_testset` without `finish` so Fail/Error
# stay off the parent suite (counts unchanged). Printing is suppressed.

function _digest_probe_testset(body, desc::AbstractString)
    ts = Test.DefaultTestSet(desc; failfast = false)
    Base.ScopedValues.@with Test.TESTSET_PRINT_ENABLE => false begin
        Test.@with_testset ts begin
            body()
        end
    end
    return ts
end

@testset "failure digest" begin
    @testset "lists Fail with file:line" begin
        ts = _digest_probe_testset("probe-fail") do
            @testset "inner" begin
                @test 1 == 2
            end
        end
        text = format_failure_digest(ts)
        @test startswith(text, FAILURE_DIGEST_MARKER)
        @test occursin("FAIL  probe-fail / inner  ", text)
        @test occursin("test/test_failure_digest.jl:", text)
        @test occursin("1 == 2", text)
        @test !occursin("no failures", text)
    end

    @testset "lists Error with file:line" begin
        ts = _digest_probe_testset("probe-error") do
            @test error("digest-probe-error")
        end
        text = format_failure_digest(ts)
        @test occursin("ERROR  probe-error  ", text)
        @test occursin("test/test_failure_digest.jl:", text)
        @test occursin("digest-probe-error", text)
    end

    @testset "clean testset prints no failures" begin
        ts = _digest_probe_testset("probe-clean") do
            return nothing
        end
        text = format_failure_digest(ts)
        @test text == FAILURE_DIGEST_MARKER * "\nno failures\n"
    end

    @testset "caps entries and counts the rest" begin
        ts = _digest_probe_testset("probe-cap") do
            for i in 1:51
                @test i == 0
            end
        end
        text = format_failure_digest(ts; max_entries = 50)
        @test occursin("... and 1 more (50 shown)", text)
        n_fail_lines = count(l -> startswith(l, "FAIL  "), split(text, '\n'))
        @test n_fail_lines == 50
    end
end
