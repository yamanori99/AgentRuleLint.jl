@testset "expect-audit placement and parsing" begin
    @testset "parse_expect_body rejects empty and whitespace-only reason" begin
        for body in (
                "jailint-expect: foo reason=\"\"",
                "jailint-expect: foo reason=\"   \"",
            )
            p = JAILint.parse_expect_body(body)
            @test p !== nothing
            @test p.status == :malformed
            @test p.message == "empty reason"
        end
        p = JAILint.parse_expect_body("jailint-expect: foo reason=\"ok\"")
        @test p.status == :ok
    end

    @testset "rule anchor kinds" begin
        @test JAILint.rule_anchor_matches("silent-catch", "try")
        @test !JAILint.rule_anchor_matches("silent-catch", "catch e")
        @test !JAILint.rule_anchor_matches("silent-catch", "x = 1")
        @test JAILint.rule_anchor_matches("test-integrity", "@test x == 1")
        @test JAILint.rule_anchor_matches("test-integrity", "@testset \"s\" begin end")
        @test JAILint.rule_anchor_matches("unsafe-boundary", "@eval x")
        @test JAILint.rule_anchor_matches("unsafe-boundary", "ccall(:q, Cvoid, ())")
        @test JAILint.rule_anchor_matches("shell-safety/process-pattern", "run(`ls`)")
        @test JAILint.rule_anchor_matches("shell-safety/process-pattern", "Cmd(\"ls\")")
        @test JAILint.rule_anchor_matches("project/no-x", "anything()")
        @test !JAILint.rule_anchor_matches("unknown-built-in", "try")
    end

    corpus = joinpath(ROOT, "test", "corpus")
    rel = p -> joinpath("test", "corpus", p)

    function check_path(path)
        return JAILint.check(ROOT; paths = [path])
    end

    function has_diag(path, pred)
        return any(pred, check_path(path).violations)
    end

    function project_hit(path; suppressed = nothing)
        hits = filter(
            d -> d.rule_id == "project/no-internal-codename" && d.path == path,
            check_path(path).violations,
        )
        unsup = filter(!d -> d.suppressed, hits)
        sup = filter(d -> d.suppressed, hits)
        if suppressed === true
            return !isempty(sup) && isempty(unsup)
        elseif suppressed === false
            return !isempty(unsup)
        end
        return !isempty(hits)
    end

    @testset "corpus expect-audit placement" begin
        @test has_diag(rel("expect_empty_reason.jl"), d -> occursin("empty reason", d.message))
        @test has_diag(rel("expect_whitespace_reason.jl"), d -> occursin("empty reason", d.message))
        @test has_diag(rel("expect_anchor_mismatch.jl"), d -> occursin("not anchored", d.message))
        @test has_diag(rel("expect_above_catch.jl"), d -> occursin("above catch", d.message))
        @test has_diag(
            rel("expect_multiline_call.jl"),
            d -> occursin("multiline call", d.message) && d.level == :forbid,
        )
        @test has_diag(rel("expect_runic_off.jl"), d -> occursin("runic:off", d.message))
        @test !has_diag(
            rel("expect_anchor_try_ok.jl"),
            d -> d.rule_id == "expect-audit" && occursin("not anchored", d.message),
        )
        @test !has_diag(
            rel("expect_above_try_not_catch.jl"),
            d -> d.rule_id == "expect-audit" && occursin("above catch", d.message),
        )
        @test !has_diag(
            rel("expect_multiline_call_outside.jl"),
            d -> occursin("multiline call", d.message),
        )
        @test !has_diag(
            rel("expect_runic_off_outside.jl"),
            d -> occursin("runic:off", d.message),
        )
        @test project_hit(rel("expect_runic_off_outside.jl"); suppressed = true)
    end

    @testset "forbidden expects do not suppress project findings" begin
        @test project_hit(rel("expect_runic_off_suppress.jl"); suppressed = false)
        @test project_hit(rel("expect_multiline_call_suppress.jl"); suppressed = false)
        @test project_hit(rel("expect_above_catch_suppress.jl"); suppressed = false)
        @test project_hit(rel("expect_anchor_mismatch_suppress.jl"); suppressed = false)
    end

    @testset "invalid expects do not suppress project findings" begin
        @test project_hit(rel("expect_empty_reason.jl"); suppressed = false)
        @test project_hit(rel("expect_whitespace_reason.jl"); suppressed = false)
        @test project_hit(rel("expect_blank_line.jl"); suppressed = false)
    end

    @testset "mixed group per-rule anchor" begin
        @test has_diag(
            rel("expect_mixed_group_anchor.jl"),
            d -> d.anchor_line == 2 && occursin("not anchored", d.message),
        )
        @test project_hit(rel("expect_mixed_group_anchor.jl"); suppressed = true)
    end

    @testset "check() path: trailing and malformed" begin
        @test has_diag(
            rel("trailing_expect.jl"),
            d -> d.rule_id == "expect-audit" && occursin("trailing inline", d.message),
        )
        @test has_diag(
            "test/corpus/trailing_expect.jl",
            d -> d.rule_id == "expect-audit" && !d.suppressed,
        )
    end

    @testset "detect_malformed_jailint uses trailing helper" begin
        src = "x = 1 # jailint-expect: foo reason=\"y\"\n"
        @test any(d -> d[2] == "trailing inline expect", JAILint.detect_malformed_jailint(src))
        src2 = "# jailint-nope\n"
        @test any(d -> occursin("malformed", d[2]), JAILint.detect_malformed_jailint(src2))
    end
end
