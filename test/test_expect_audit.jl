@testset "expect-audit placement and parsing" begin
    @testset "parse_expect_body rejects empty reason" begin
        p = JAILint.parse_expect_body("jailint-expect: foo reason=\"\"")
        @test p !== nothing
        @test p.status == :malformed
        @test p.message == "empty reason"
    end

    @testset "rule anchor kinds" begin
        @test JAILint.rule_anchor_matches("silent-catch", "try")
        @test JAILint.rule_anchor_matches("silent-catch", "catch e")
        @test !JAILint.rule_anchor_matches("silent-catch", "x = 1")
        @test JAILint.rule_anchor_matches("test-integrity", "@test x == 1")
        @test JAILint.rule_anchor_matches("project/no-x", "anything()")
        @test !JAILint.rule_anchor_matches("unknown-built-in", "try")
    end

    corpus = joinpath(ROOT, "test", "corpus")

    @testset "corpus expect-audit gaps" begin
        function has_diag(path, pred)
            res = JAILint.check(ROOT; paths = [path])
            return any(pred, res.violations)
        end

        rel = p -> joinpath("test", "corpus", p)
        @test has_diag(rel("expect_empty_reason.jl"), d -> occursin("empty reason", d.message))
        @test has_diag(rel("expect_anchor_mismatch.jl"), d -> occursin("not anchored", d.message))
        @test has_diag(rel("expect_above_catch.jl"), d -> occursin("above catch", d.message))
        @test has_diag(
            rel("expect_multiline_call.jl"),
            d -> occursin("multiline call", d.message) && d.level == :warn,
        )
        @test has_diag(rel("expect_runic_off.jl"), d -> occursin("runic:off", d.message))
        @test !has_diag(
            rel("expect_anchor_try_ok.jl"),
            d -> d.rule_id == "expect-audit" && occursin("not anchored", d.message),
        )
    end

    @testset "detect_malformed_jailint wired" begin
        src = "# jailint-nope\n"
        diags = JAILint.detect_malformed_jailint(src)
        @test any(d -> occursin("malformed", d[2]), diags)
    end
end
