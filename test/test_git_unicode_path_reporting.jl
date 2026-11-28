using AgentRuleLint
using Test

# NFC "é" (U+00E9); NFD is U+0065 U+0301 (see `_UNICODE_REL_NFD`).
const _UNICODE_REL_NFC = "caf\u00e9 x.jl"
const _UNICODE_REL_NFD = "cafe\u0301 x.jl"

function _unicode_rel_cfg()
    ver = string(pkgversion(AgentRuleLint))
    return """
    agentrulelint_version = \"=$(ver)\"

    [[project_rules]]
    id = \"diff-literal\"
    level = \"deny\"
    paths = [\"**/*.jl\"]
    forbid_literals = [\"FORBIDDEN_DIFF_TOKEN\"]
    intent = \"\"
    do_not = \"\"
    """
end

function _unicode_violation_paths(res::AgentRuleLint.CheckResult)
    out = String[]
    for d in res.violations
        b = basename(d.path)
        (b == _UNICODE_REL_NFC || b == _UNICODE_REL_NFD) && push!(out, d.path)
    end
    return unique(out)
end

@testset "bundled git unicode path reporting (Git_jll precomposeunicode=false on macOS)" begin
    @testset "plain check and check --diff agree on reported path" begin
        dir = abspath(mktempdir())
        try
            init_git_repo!(dir)
            write(joinpath(dir, ".AgentRuleLint.jl.toml"), _unicode_rel_cfg())
            write(joinpath(dir, _UNICODE_REL_NFC), "1\n")
            git_commit_all!(dir, "base")
            write(joinpath(dir, _UNICODE_REL_NFC), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
            git_commit_all!(dir, "change")
            cd(dir) do
                res_plain = AgentRuleLint.check(dir)
                res_diff = AgentRuleLint.check(dir; diff_base = "HEAD^1")
                paths_plain = _unicode_violation_paths(res_plain)
                paths_diff = _unicode_violation_paths(res_diff)
                git_index_path = strip(
                    String(
                        read_git_cmd(
                            dir,
                            "-c",
                            "core.quotepath=false",
                            "ls-files",
                            "--",
                            _UNICODE_REL_NFC;
                            error_prefix = "git ls-files",
                        ),
                    ),
                )
                @test !isempty(paths_plain)
                @test paths_plain == paths_diff
                @test only(paths_plain) == only(paths_diff)
                @test only(paths_plain) == git_index_path
                println(
                    "unicode path reporting: ls-files=",
                    repr(git_index_path),
                    " plain=",
                    repr(only(paths_plain)),
                    " diff=",
                    repr(only(paths_diff)),
                    " nfc_input=",
                    repr(_UNICODE_REL_NFC),
                    " nfd_input=",
                    repr(_UNICODE_REL_NFD),
                    " apple=",
                    Sys.isapple(),
                )
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end

end