@testset "unsafe-boundary rule" begin
    _UNSAFE_POSITIVE = String[
        "unsafe_ccall.jl",
        "unsafe_eval_runtime.jl",
        "unsafe_meta_parse.jl",
        "unsafe_indirect_eval.jl",
        "unsafe_intrinsic_call.jl",
        "unsafe_evasion_const_eval.jl",
        "unsafe_qualified_names.jl",
        "unsafe_value_alias.jl",
        "unsafe_default_kwarg.jl",
    ]

    _UNSAFE_STRICT_POSITIVE = String[
        "unsafe_inbounds.jl",
        "unsafe_assume_effects_macro.jl",
    ]

    _UNSAFE_NEGATIVE = String[
        "unsafe_toplevel_eval_literal.jl",
        "unsafe_function_def.jl",
        "unsafe_macro_substring_negative.jl",
    ]

    function _unsafe_hits(root::AbstractString, relpath::AbstractString)
        res = AgentRuleLint.check(root; paths = [joinpath("test", "corpus", relpath)])
        return filter(
            d -> d.rule_id == "unsafe-boundary" && !d.suppressed,
            res.violations,
        )
    end

    function _unsafe_strict_hits(root::AbstractString, relpath::AbstractString)
        res = AgentRuleLint.check(root; paths = [joinpath("test", "corpus", relpath)])
        rid = AgentRuleLint.UNSAFE_BOUNDARY_STRICT_PRESET_ID
        return filter(d -> d.rule_id == rid && !d.suppressed, res.violations)
    end

    function _minimal_config_with_unsafe(extra::AbstractString = "")
        v = string(pkgversion(AgentRuleLint))
        globs = occursin("allow_globs", extra) ? "" : "allow_globs = []\n"
        mods = occursin("allow_modules", extra) ? "" : "allow_modules = []\n"
        return """
        agentrulelint_version = \"=$(v)\"
        default_format = \"human\"
        [rules.expect-audit]
        level = \"forbid\"
        on_allow_rule = \"warn\"
        [rules.unsafe-boundary]
        level = \"deny\"
        $mods$globs$extra
        """
    end

    function _minimal_config_with_unsafe_strict(extra::AbstractString = "")
        v = string(pkgversion(AgentRuleLint))
        globs = occursin("allow_globs", extra) ? "" : "allow_globs = []\n"
        mods = occursin("allow_modules", extra) ? "" : "allow_modules = []\n"
        return """
        agentrulelint_version = \"=$(v)\"
        default_format = \"human\"
        presets = [\"unsafe-boundary/strict\"]
        [rules.expect-audit]
        level = \"forbid\"
        on_allow_rule = \"warn\"
        [rules.unsafe-boundary]
        level = \"deny\"
        $mods$globs$extra
        [rules.\"unsafe-boundary/strict\"]
        level = \"deny\"
        """
    end

    function _mutation_detector_subprocess(
            repo_root::AbstractString,
            source_relpath::AbstractString,
            patched::AbstractString;
            corpus::AbstractString,
            msg_needle::AbstractString,
            rule_id::AbstractString = "unsafe-boundary",
            config_toml::Union{Nothing, AbstractString} = nothing,
        )
        script = root -> join(
            [
                "using AgentRuleLint",
                "r = AgentRuleLint.check($(repr(root)); paths=[joinpath(\"test\", \"corpus\", $corpus)])",
                "h = filter(d -> d.rule_id == $(repr(rule_id)) && occursin($(repr(msg_needle)), d.message), r.violations)",
                "exit(isempty(h) ? 0 : 1)",
            ],
            '\n',
        )
        tmp = mktempdir()
        try
            cp(repo_root, tmp; force = true)
            if config_toml !== nothing
                write(joinpath(tmp, ".AgentRuleLintConfig.toml"), config_toml)
            end
            base_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script(tmp))`
            before_ok = success(run(ignorestatus(setenv(base_cmd; dir = repo_root))))
            write(joinpath(tmp, source_relpath), patched)
            patch_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script(tmp))`
            after_ok = success(run(ignorestatus(setenv(patch_cmd; dir = repo_root))))
            return (!before_ok, after_ok)
        finally
            rm(tmp, recursive = true, force = true)
        end
    end

    repo_root = dirname(@__DIR__)

    @testset "golden corpus hits" begin
        for file in _UNSAFE_POSITIVE
            hits = _unsafe_hits(repo_root, file)
            @test !isempty(hits)
        end
    end

    @testset "negative corpus clean" begin
        for file in _UNSAFE_NEGATIVE
            hits = _unsafe_hits(repo_root, file)
            @test isempty(hits)
        end
    end

    @testset "strict macros absent without preset" begin
        for file in _UNSAFE_STRICT_POSITIVE
            @test isempty(_unsafe_hits(repo_root, file))
            @test isempty(_unsafe_strict_hits(repo_root, file))
        end
    end

    @testset "strict preset macro corpus" begin
        root = mktempdir()
        try
            cp(repo_root, root; force = true)
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _minimal_config_with_unsafe_strict())
            for file in _UNSAFE_STRICT_POSITIVE
                hits = _unsafe_strict_hits(root, file)
                @test !isempty(hits)
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "strict rule table without preset is ConfigError" begin
        root = mktempdir()
        try
            v = string(pkgversion(AgentRuleLint))
            write(
                joinpath(root, ".AgentRuleLintConfig.toml"),
                """
                agentrulelint_version = \"=$(v)\"
                default_format = \"human\"
                [rules.expect-audit]
                level = \"forbid\"
                on_allow_rule = \"warn\"
                [rules.unsafe-boundary]
                level = \"deny\"
                allow_modules = []
                allow_globs = []
                [rules.\"unsafe-boundary/strict\"]
                level = \"warn\"
                """,
            )
            @test_throws AgentRuleLint.ConfigError AgentRuleLint.check(root)
        finally
            rm(root, recursive = true, force = true)
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

    @testset "mutation: detector source patches (subprocess)" begin
        unsafe_src = joinpath(repo_root, "src", "rules", "unsafe_boundary.jl")
        builtin_src = joinpath(repo_root, "src", "rules", "builtin_rules.jl")
        unsafe_orig = read(unsafe_src, String)
        builtin_orig = read(builtin_src, String)

        cases = [
            (
                "eval",
                unsafe_src,
                unsafe_orig,
                "_matches_qualified_leaf(fname, \"eval\")" => "false",
                "unsafe_eval_runtime.jl",
                "runtime eval",
            ),
            (
                "Meta.parse",
                unsafe_src,
                unsafe_orig,
                "_matches_meta_parse_call(fname)" => "false",
                "unsafe_meta_parse.jl",
                "Meta.parse",
            ),
            (
                "ccall",
                unsafe_src,
                unsafe_orig,
                "_matches_qualified_leaf(fname, \"ccall\")" => "false",
                "unsafe_ccall.jl",
                "ccall",
            ),
            (
                "unsafe_*",
                unsafe_src,
                unsafe_orig,
                "_julia_unsafe_intrinsic_callee(fname)" => "false",
                "unsafe_intrinsic_call.jl",
                "unsafe_*",
            ),
            (
                "invokelatest",
                unsafe_src,
                unsafe_orig,
                "_matches_qualified_leaf(fname, \"invokelatest\")" => "false",
                "unsafe_qualified_names.jl",
                "invokelatest",
            ),
            (
                "macros",
                unsafe_src,
                unsafe_orig,
                "macro_label = _unsafe_macro_label(mname, ctx.macro_suffixes)" =>
                    "macro_label = \"\"",
                "unsafe_inbounds.jl",
                "@inbounds",
            ),
            (
                "value alias",
                unsafe_src,
                unsafe_orig,
                "function _is_boundary_value_ref(refname::AbstractString)\n    refname == \"\"" =>
                    "function _is_boundary_value_ref(refname::AbstractString)\n    return false\n    refname == \"\"",
                "unsafe_value_alias.jl",
                "boundary value",
            ),
            (
                "allow_modules gating",
                unsafe_src,
                unsafe_orig,
                "_in_allowed_module(ctx.module_stack, ctx.allow_modules)" => "false",
                "unsafe_ccall.jl",
                "ccall",
            ),
        ]

        for (label, _, orig, pair, corpus, needle) in cases
            @testset "$label" begin
                if label == "allow_modules gating"
                    cfg_root = mktempdir()
                    cp(repo_root, cfg_root; force = true)
                    write(
                        joinpath(cfg_root, ".AgentRuleLintConfig.toml"),
                        _minimal_config_with_unsafe("allow_modules = [\"BoundarySafe\"]\n"),
                    )
                    script = join(
                        [
                            "using AgentRuleLint",
                            "root = $(repr(cfg_root))",
                            "p = joinpath(root, \"test\", \"corpus\", \"unsafe_allow_module.jl\")",
                            "r = AgentRuleLint.check(root; paths=[p])",
                            "h = filter(d -> d.rule_id == \"unsafe-boundary\", r.violations)",
                            "exit(isempty(h) ? 0 : 1)",
                        ],
                        '\n',
                    )
                    tmp = mktempdir()
                    try
                        cp(repo_root, tmp; force = true)
                        base_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script)`
                        @test success(run(ignorestatus(setenv(base_cmd; dir = repo_root))))
                        patched = replace(orig, pair)
                        write(joinpath(tmp, "src", "rules", "unsafe_boundary.jl"), patched)
                        patch_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script)`
                        @test !success(run(ignorestatus(setenv(patch_cmd; dir = repo_root))))
                    finally
                        rm(tmp, recursive = true, force = true)
                        rm(cfg_root, recursive = true, force = true)
                    end
                else
                    patched = replace(orig, pair)
                    strict = label == "macros"
                    found_before, missed_after = _mutation_detector_subprocess(
                        repo_root,
                        "src/rules/unsafe_boundary.jl",
                        patched;
                        corpus = repr(corpus),
                        msg_needle = needle,
                        rule_id = strict ? AgentRuleLint.UNSAFE_BOUNDARY_STRICT_PRESET_ID :
                            "unsafe-boundary",
                        config_toml = strict ? _minimal_config_with_unsafe_strict() : nothing,
                    )
                    @test found_before
                    @test missed_after
                end
            end
        end

        @testset "allow_globs gating" begin
            globs_root = mktempdir()
            try
                cp(repo_root, globs_root; force = true)
                write(
                    joinpath(globs_root, ".AgentRuleLintConfig.toml"),
                    _minimal_config_with_unsafe("allow_globs = [\"**\"]\n"),
                )
                script = join(
                    [
                        "using AgentRuleLint",
                        "r = AgentRuleLint.check($(repr(globs_root)); paths=[joinpath(\"test\", \"corpus\", \"unsafe_ccall.jl\")])",
                        "h = filter(d -> d.rule_id == \"unsafe-boundary\", r.violations)",
                        "exit(isempty(h) ? 0 : 1)",
                    ],
                    '\n',
                )
                tmp = mktempdir()
                try
                    cp(repo_root, tmp; force = true)
                    base_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script)`
                    @test success(run(ignorestatus(setenv(base_cmd; dir = repo_root))))
                    patched = replace(
                        builtin_orig,
                        "path_matches_glob(fc.parsed.path, cfg.allow_globs) && return diags" =>
                            "false && return diags",
                    )
                    write(joinpath(tmp, "src", "rules", "builtin_rules.jl"), patched)
                    patch_cmd = `julia --compiled-modules=no --startup-file=no --project=$(tmp) -e $(script)`
                    @test !success(run(ignorestatus(setenv(patch_cmd; dir = repo_root))))
                finally
                    rm(tmp, recursive = true, force = true)
                end
            finally
                rm(globs_root, recursive = true, force = true)
            end
        end

    end
end
