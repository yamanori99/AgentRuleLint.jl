using AgentRuleLint
using Test

# Built from code points only (not editor-typed literals).
const _NFC_BASENAME = string("nfc_", Char(0x00E9), ".jl")  # …e + U+00E9 (NFC é)
const _NFD_BASENAME = string("nfd_", Char(0x0065), Char(0x0301), ".jl")  # …e + U+0301 (NFD é)

function _bytes_hex(v)
    return join(string.(codeunits(v), base = 16, pad = 2), " ")
end

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

function _git_ls_files_z_paths(dir::AbstractString)
    raw = read_git_cmd(dir, "ls-files", "-z"; error_prefix = "git ls-files -z")
    blobs = split(String(raw), '\0'; keepempty = false)
    return [String(p) for p in blobs]
end

function _find_git_path(paths::Vector{String}, prefix::AbstractString)
    pre = String(prefix)
    for p in paths
        startswith(basename(p), pre) && return String(p)
    end
    return ""
end

function _violation_path_with_prefix(res::AgentRuleLint.CheckResult, prefix::AbstractString)
    pre = String(prefix)
    for d in res.violations
        d.rule_id == "project/diff-literal" || continue
        startswith(basename(d.path), pre) && return String(d.path)
    end
    return ""
end

function _report_unicode_file!(
        dir::AbstractString,
        written_rel::AbstractString,
        path_prefix::AbstractString,
        diff_base::AbstractString,
    )
    written_rel = String(written_rel)
    paths = _git_ls_files_z_paths(dir)
    ls = _find_git_path(paths, path_prefix)
    ls == "" && error("git ls-files -z missing prefix $(repr(path_prefix))")
    res_plain = AgentRuleLint.check(dir)
    res_diff = AgentRuleLint.check(dir; diff_base = diff_base)
    plain_p = _violation_path_with_prefix(res_plain, path_prefix)
    diff_p = _violation_path_with_prefix(res_diff, path_prefix)
    plain_p == "" && error("plain check missing violation for $(repr(written_rel))")
    diff_p == "" && error("diff check missing violation for $(repr(written_rel))")
    plain_b = basename(plain_p)
    diff_b = basename(diff_p)
    ls_b = basename(ls)
    println(
        "unicode codeunits label=$(Sys.isapple() ? "macos" : "linux") ",
        "written_nfc_nfd=$(written_rel == _NFC_BASENAME ? "nfc" : "nfd") ",
        "written=", _bytes_hex(written_rel), " ",
        "ls-files=", _bytes_hex(ls_b), " ",
        "plain=", _bytes_hex(plain_b), " ",
        "diff=", _bytes_hex(diff_b),
    )
    @test codeunits(ls_b) == codeunits(plain_b)
    @test codeunits(ls_b) == codeunits(diff_b)
    return nothing
end

@testset "bundled git unicode path reporting (Git_jll precomposeunicode=false on macOS)" begin
    dir = abspath(mktempdir())
    try
        init_git_repo!(dir)
        write(joinpath(dir, ".AgentRuleLint.jl.toml"), _unicode_rel_cfg())
        println(
            "unicode codeunits written_basenames: ",
            "nfc=", _bytes_hex(_NFC_BASENAME), " ",
            "nfd=", _bytes_hex(_NFD_BASENAME),
        )
        write(joinpath(dir, _NFC_BASENAME), "1\n")
        write(joinpath(dir, _NFD_BASENAME), "1\n")
        git_commit_all!(dir, "base")
        write(joinpath(dir, _NFC_BASENAME), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
        write(joinpath(dir, _NFD_BASENAME), "x = \"FORBIDDEN_DIFF_TOKEN\"\n")
        git_commit_all!(dir, "change")
        cd(dir) do
            _report_unicode_file!(dir, _NFC_BASENAME, "nfc_", "HEAD^1")
            _report_unicode_file!(dir, _NFD_BASENAME, "nfd_", "HEAD^1")
        end
    finally
        rm(dir, recursive = true, force = true)
    end
end
