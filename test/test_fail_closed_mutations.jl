@testset "fail-closed mutation guards (formatter / diff parser)" begin
    ROOT = normpath(joinpath(@__DIR__, ".."))

    function _mutation_expect_fail(desc::String, rel_path::String, needle::String, replacement::String, check_cmd::String)
        src_path = joinpath(ROOT, rel_path)
        orig = read(src_path, String)
        occursin(needle, orig) || error("mutation needle missing for $desc")
        write(src_path, replace(orig, needle => replacement, count = 1))
        try
            parts = split(check_cmd)
            cmd = Cmd(parts)
            ok = cd(ROOT) do
                success(setenv(cmd; dir = ROOT))
            end
            ok && error("mutation for $desc: fail-closed check still passed")
            return desc
        finally
            write(src_path, orig)
        end
    end

    @testset "diff parser: unknown status must not continue" begin
        _mutation_expect_fail(
            "diff name-status unknown",
            joinpath("src", "diff.jl"),
            "throw(GitError(\"unknown git diff name-status '\$status'\"))",
            "continue",
            "julia --startup-file=no --project=. -e \"using Test, AgentRuleLint; @test_throws AgentRuleLint.GitError AgentRuleLint._parse_diff_path_events_payload(\\\"X\\0x\\0\\\")\"",
        )
    end

    @testset "explain: no default_policy fallback on ConfigError" begin
        _mutation_expect_fail(
            "explain default_policy fallback",
            joinpath("src", "format", "report.jl"),
            "policy = resolve_policy(root)",
            "policy = try resolve_policy(root) catch; default_policy(root) end",
            "julia --startup-file=no --project=. test/test_explain_invalid_config.jl",
        )
    end
end
