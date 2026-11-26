@testset "expect-audit placement and parsing" begin
    @testset "parse_expect_body rejects empty and whitespace-only reason" begin
        for body in (
                "agentrulelint-expect: foo reason=\"\"",
                "agentrulelint-expect: foo reason=\"   \"",
            )
            p = AgentRuleLint.parse_expect_body(body)
            @test p !== nothing
            @test p.status == :malformed
            @test p.message == "empty reason"
        end
        p_ok = AgentRuleLint.parse_expect_body("agentrulelint-expect: foo reason=\"ok\"")
        @test p_ok !== nothing
        @test p_ok.status == :ok
    end

    @testset "rule anchor kinds" begin
        @test AgentRuleLint.rule_anchor_matches("silent-catch", "try")
        @test !AgentRuleLint.rule_anchor_matches("silent-catch", "catch e")
        @test !AgentRuleLint.rule_anchor_matches("silent-catch", "x = 1")
        @test AgentRuleLint.rule_anchor_matches("test-integrity", "@test x == 1")
        @test AgentRuleLint.rule_anchor_matches("test-integrity", "@testset \"s\" begin end")
        @test AgentRuleLint.rule_anchor_matches("unsafe-boundary", "@eval x")
        @test AgentRuleLint.rule_anchor_matches("unsafe-boundary", "ccall(:q, Cvoid, ())")
        @test AgentRuleLint.rule_anchor_matches("shell-safety/process-pattern", "run(`ls`)")
        @test AgentRuleLint.rule_anchor_matches("shell-safety/process-pattern", "Cmd(\"ls\")")
        @test AgentRuleLint.rule_anchor_matches("project/no-x", "anything()")
        @test !AgentRuleLint.rule_anchor_matches("unknown-built-in", "try")
    end

    rel = p -> joinpath("test", "corpus", p)

    function check_path(path)
        return AgentRuleLint.check(ROOT; paths = [path])
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

    @testset "detect_malformed_agentrulelint uses trailing helper" begin
        src = "x = 1 # agentrulelint-expect: foo reason=\"y\"\n"
        @test any(d -> d[2] == "trailing inline expect", AgentRuleLint.detect_malformed_agentrulelint(src))
        src2 = "# agentrulelint-nope\n"
        @test any(d -> occursin("malformed", d[2]), AgentRuleLint.detect_malformed_agentrulelint(src2))
    end

    @testset "text path: extract_expect_lines_text skips malformed" begin
        src = "# agentrulelint-expect: project/no-internal-codename reason=\"\"\nval = 1\n"
        @test isempty(AgentRuleLint.extract_expect_lines_text(src))
        ok_src =
            "# agentrulelint-expect: project/no-internal-codename reason=\"ok\"\nval = 1\n"
        got = AgentRuleLint.extract_expect_lines_text(ok_src)
        @test length(got) == 1
        @test got[1].rule_ref == "project/no-internal-codename"
    end

    @testset "text path corpus expect-audit" begin
        @test project_hit(rel("expect_text_standalone.toml"); suppressed = true)
        @test !has_diag(
            rel("expect_text_standalone.toml"),
            d -> d.rule_id == "expect-audit",
        )
        @test has_diag(
            rel("expect_text_blank_line.yml"),
            d -> occursin("blank line", d.message),
        )
        @test project_hit(rel("expect_text_blank_line.yml"); suppressed = false)
        @test has_diag(
            rel("expect_text_anchor_mismatch.sh"),
            d -> occursin("not anchored", d.message),
        )
        @test project_hit(rel("expect_text_anchor_mismatch.sh"); suppressed = false)
        @test has_diag(
            rel("expect_text_mixed_group.toml"),
            d -> d.anchor_line == 2 && occursin("not anchored", d.message),
        )
        @test project_hit(rel("expect_text_mixed_group.toml"); suppressed = true)
        @test has_diag(rel("expect_text_malformed.toml"), d -> occursin("empty reason", d.message))
        @test has_diag(
            rel("expect_text_malformed.toml"),
            d -> occursin("malformed # agentrulelint", d.message),
        )
        @test has_diag(
            rel("expect_text_malformed.toml"),
            d -> occursin("block comment expect", d.message),
        )
        @test project_hit(rel("expect_text_malformed.toml"); suppressed = false)
    end

    @testset "text path: detect_malformed_agentrulelint_text" begin
        src = "# agentrulelint-expect: foo reason=\"\"\n# agentrulelint-foo\n"
        diags = AgentRuleLint.detect_malformed_agentrulelint_text(src)
        @test any(d -> d[2] == "empty reason", diags)
        @test any(d -> occursin("malformed # agentrulelint", d[2]), diags)
    end
end
