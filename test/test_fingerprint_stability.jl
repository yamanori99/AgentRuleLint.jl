using Test

const ROOT = dirname(@__DIR__)

function violation_fps(res::CheckResult, pred)
    return [d.fingerprint for d in res.violations if pred(d)]
end

function sole_fp(res::CheckResult, pred)
    fps = violation_fps(res, pred)
    length(fps) == 1 || error("expected one fingerprint, got $(length(fps))")
    return only(fps)
end

@testset "diagnostic fingerprint stability (line-independent)" begin
    corpus_tmp = joinpath("test", "corpus", "fingerprint_tmp")
    project_rel = joinpath(corpus_tmp, "project_hit.jl")
    expect_rel = joinpath(corpus_tmp, "expect_hit.jl")

    function write_and_check(rel::AbstractString, content::AbstractString)
        abs = joinpath(ROOT, rel)
        mkpath(dirname(abs))
        write(abs, content)
        return JAILint.check(ROOT; paths = [rel])
    end

    try
        mkpath(joinpath(ROOT, corpus_tmp))

        @testset "project rule: blank lines above do not change fingerprint" begin
            base = "hit = \"INTERNAL_CODENAME\"\n"
            shifted = "\n\nunrelated = 1\n\n" * base
            fp0 = sole_fp(
                write_and_check(project_rel, base),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            fp1 = sole_fp(
                write_and_check(project_rel, shifted),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            @test fp0 == fp1
        end

        @testset "project rule: changing hit code changes fingerprint" begin
            a = sole_fp(
                write_and_check(project_rel, "hit = \"INTERNAL_CODENAME\"\n"),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            b = sole_fp(
                write_and_check(project_rel, "hit = \"INT\" * \"ERNAL_CODENAME\"\n"),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            @test a != b
        end

        @testset "two identical hits: distinct and stable under insertions" begin
            base = "a = \"INTERNAL_CODENAME\"\nb = \"INTERNAL_CODENAME\"\n"
            mid = "a = \"INTERNAL_CODENAME\"\n\nx = 0\n\nb = \"INTERNAL_CODENAME\"\n"
            top = "\n\n" * base
            res0 = write_and_check(project_rel, base)
            fps0 = sort(
                violation_fps(
                    res0,
                    d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
                ),
            )
            @test length(fps0) == 2
            @test fps0[1] != fps0[2]
            fps_mid = sort(
                violation_fps(
                    write_and_check(project_rel, mid),
                    d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
                ),
            )
            @test fps0 == fps_mid
            fps_top = sort(
                violation_fps(
                    write_and_check(project_rel, top),
                    d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
                ),
            )
            @test fps0 == fps_top
        end

        @testset "whitespace-only reindent of anchor keeps fingerprint" begin
            loose = "  hit   =   \"INTERNAL_CODENAME\"  \n"
            tight = "hit = \"INTERNAL_CODENAME\"\n"
            fp_loose = sole_fp(
                write_and_check(project_rel, loose),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            fp_tight = sole_fp(
                write_and_check(project_rel, tight),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            @test fp_loose == fp_tight
        end

        @testset "expect-audit: blank lines above do not change fingerprint" begin
            base =
                "# jailint-expect: project/no-internal-codename reason=\"x\"\n\nhit = \"INTERNAL_CODENAME\"\n"
            shifted = "\n\n\n" * base
            pred = d -> d.rule_id == "expect-audit" && occursin("blank line", d.message)
            fp0 = sole_fp(write_and_check(expect_rel, base), pred)
            fp1 = sole_fp(write_and_check(expect_rel, shifted), pred)
            @test fp0 == fp1
        end

        @testset "report resolves fingerprint after line shift" begin
            base = "hit = \"INTERNAL_CODENAME\"\n"
            shifted = "\n\n\n" * base
            fp = sole_fp(
                write_and_check(project_rel, base),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            write_and_check(project_rel, shifted)
            cd(ROOT) do
                @test JAILint.cli_main(["report", fp]) == 0
            end
        end

        @testset "different path or rule_id yields different fingerprint" begin
            rel2 = joinpath(corpus_tmp, "other_path.jl")
            body = "hit = \"INTERNAL_CODENAME\"\n"
            fp1 = sole_fp(
                write_and_check(project_rel, body),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            fp2 = sole_fp(
                write_and_check(rel2, body),
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            @test fp1 != fp2
            expect_bad = "# jailint-expect: foo reason=\"\"\n"
            fp3 = sole_fp(
                write_and_check(expect_rel, expect_bad),
                d -> d.rule_id == "expect-audit",
            )
            @test fp1 != fp3
        end

        @testset "unicode project anchor: no internal error and stable fingerprint" begin
            uni_rel = joinpath(corpus_tmp, "unicode_project.jl")
            base = "x = \"INTERNAL_CODENAME🙂\"\n"
            shifted = "\n\n" * base
            res0 = write_and_check(uni_rel, base)
            @test res0.complete
            @test res0.exit_code == 1
            fp0 = sole_fp(
                res0,
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            res1 = write_and_check(uni_rel, shifted)
            @test res1.complete
            @test res1.exit_code == 1
            fp1 = sole_fp(
                res1,
                d -> d.rule_id == "project/no-internal-codename" && !d.suppressed,
            )
            @test fp0 == fp1
            cd(ROOT) do
                @test JAILint.cli_main(["check", uni_rel]) == 1
            end
        end

        @testset "unicode expect-audit comment: no internal error and stable fingerprint" begin
            uni_rel = joinpath(corpus_tmp, "unicode_expect.jl")
            base =
                "# jailint-expect: project/no-internal-codename reason=\"注🙂意\"\n\nhit = \"INTERNAL_CODENAME\"\n"
            shifted = "\n" * base
            pred = d -> d.rule_id == "expect-audit" && occursin("blank line", d.message)
            res0 = write_and_check(uni_rel, base)
            @test res0.complete
            @test res0.exit_code == 1
            fp0 = sole_fp(res0, pred)
            res1 = write_and_check(uni_rel, shifted)
            @test res1.complete
            @test res1.exit_code == 1
            fp1 = sole_fp(res1, pred)
            @test fp0 == fp1
            alt =
                "# jailint-expect: project/no-internal-codename reason=\"別の理由\"\n\nhit = \"INTERNAL_CODENAME\"\n"
            fp_alt = sole_fp(write_and_check(uni_rel, alt), pred)
            @test fp0 != fp_alt
            cd(ROOT) do
                @test JAILint.cli_main(["check", uni_rel]) == 1
            end
        end

        @testset "payload has no line-number field" begin
            d = only(
                filter(
                    x -> x.rule_id == "project/no-internal-codename" && !x.suppressed,
                    write_and_check(project_rel, "hit = \"INTERNAL_CODENAME\"\n").violations,
                ),
            )
            @test !occursin("|$(d.anchor_line)|", d.fingerprint)
            @test startswith(d.fingerprint, "v1:")
            @test length(d.fingerprint) > 4
        end
    finally
        rm(joinpath(ROOT, corpus_tmp); force = true, recursive = true)
    end
end
