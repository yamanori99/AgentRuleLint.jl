const _UNSAFE_POSITIVE = String[
    "unsafe_ccall.jl",
    "unsafe_eval_runtime.jl",
    "unsafe_meta_parse.jl",
    "unsafe_indirect_eval.jl",
    "unsafe_inbounds.jl",
    "unsafe_intrinsic_call.jl",
    "unsafe_evasion_const_eval.jl",
]

const _UNSAFE_NEGATIVE = String[
    "unsafe_toplevel_eval_literal.jl",
    "unsafe_function_def.jl",
]

function _unsafe_hits(root::AbstractString, relpath::AbstractString)
    res = AgentRuleLint.check(root; paths = [joinpath("test", "corpus", relpath)])
    return filter(
        d -> d.rule_id == "unsafe-boundary" && !d.suppressed,
        res.violations,
    )
end

function _minimal_config_with_unsafe(extra::AbstractString = "")
    v = string(pkgversion(AgentRuleLint))
    globs = occursin("allow_globs", extra) ? "" : "allow_globs = []\n"
    return """
    agentrulelint_version = \"=$(v)\"
    default_format = \"human\"
    [rules.expect-audit]
    level = \"forbid\"
    on_allow_rule = \"warn\"
    [rules.unsafe-boundary]
    level = \"deny\"
    allow_modules = []
    $globs$extra
    """
end

@testset "unsafe-boundary rule" begin
    @testset "golden corpus hits" begin
        for file in _UNSAFE_POSITIVE
            hits = _unsafe_hits(ROOT, file)
            @test !isempty(hits)
        end
    end

    @testset "negative corpus clean" begin
        for file in _UNSAFE_NEGATIVE
            hits = _unsafe_hits(ROOT, file)
            @test isempty(hits)
        end
    end

    @testset "inactive without rules.unsafe-boundary" begin
        root = mktempdir()
        try
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _minimal_config_with_unsafe())
            cfg = read(joinpath(root, ".AgentRuleLintConfig.toml"), String)
            cfg = replace(
                cfg,
                "[rules.unsafe-boundary]\nlevel = \"deny\"\nallow_modules = []\nallow_globs = []\n" =>
                    "",
            )
            write(joinpath(root, ".AgentRuleLintConfig.toml"), cfg)
            write(joinpath(root, "bad.jl"), read(joinpath(CORPUS, "unsafe_ccall.jl"), String))
            res = AgentRuleLint.check(root; paths = ["bad.jl"])
            hits = filter(d -> d.rule_id == "unsafe-boundary", res.violations)
            @test isempty(hits)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "allow_globs suppresses file" begin
        root = mktempdir()
        try
            write(
                joinpath(root, ".AgentRuleLintConfig.toml"),
                _minimal_config_with_unsafe("allow_globs = [\"**\"]\n"),
            )
            write(joinpath(root, "bad.jl"), read(joinpath(CORPUS, "unsafe_ccall.jl"), String))
            res = AgentRuleLint.check(root; paths = ["bad.jl"])
            hits = filter(d -> d.rule_id == "unsafe-boundary", res.violations)
            @test isempty(hits)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "config fail-closed unknown unsafe-boundary key" begin
        root = mktempdir()
        try
            write(
                joinpath(root, ".AgentRuleLintConfig.toml"),
                _minimal_config_with_unsafe("typo = true\n"),
            )
            @test_throws AgentRuleLint.ConfigError AgentRuleLint.check(root)
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "mutation: ccall detector disabled (subprocess)" begin
        bak = joinpath(ROOT, "src", "rules", "unsafe_boundary.jl")
        orig = read(bak, String)
        patched = replace(
            orig,
            "fname in (\"ccall\", \"Core.ccall\")" => "fname in (\"ccall_OFF\", \"Core.ccall\")",
        )
        script = root -> join(
            [
                "using AgentRuleLint",
                "r = AgentRuleLint.check($(repr(root)); paths=[joinpath(\"test\", \"corpus\", \"unsafe_ccall.jl\")])",
                "h = filter(d -> d.rule_id == \"unsafe-boundary\" && occursin(\"ccall\", d.message), r.violations)",
                "exit(isempty(h) ? 0 : 1)",
            ],
            '\n',
        )
        tmp = mktempdir()
        try
            cp(ROOT, tmp; force = true)
            base_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script(tmp))`
            @test !success(run(ignorestatus(setenv(base_cmd; dir = ROOT))))
            write(joinpath(tmp, "src", "rules", "unsafe_boundary.jl"), patched)
            patch_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script(tmp))`
            @test success(run(ignorestatus(setenv(patch_cmd; dir = ROOT))))
        finally
            write(bak, orig)
            rm(tmp, recursive = true, force = true)
        end
    end
end
