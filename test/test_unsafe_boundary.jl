include("mutation_subprocess_helpers.jl")

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

    function _mutation_detector_script(
            root::AbstractString,
            corpus::AbstractString,
            msg_needle::AbstractString,
            rule_id::AbstractString,
        )
        return join(
            [
                "using AgentRuleLint",
                "r = AgentRuleLint.check($(repr(root)); paths=[joinpath(\"test\", \"corpus\", $corpus)])",
                "h = filter(d -> d.rule_id == $(repr(rule_id)) && occursin($(repr(msg_needle)), d.message), r.violations)",
                "exit(isempty(h) ? 0 : $(_MUTATION_HITS_EXIT))",
            ],
            '\n',
        )
    end

    function _mutation_needle_hits(
            root::AbstractString,
            corpus::AbstractString,
            needle::AbstractString;
            rule_id::AbstractString = "unsafe-boundary",
        )
        res = AgentRuleLint.check(root; paths = [joinpath("test", "corpus", corpus)])
        return filter(
            d -> d.rule_id == rule_id && occursin(needle, d.message) && !d.suppressed,
            res.violations,
        )
    end

    function _mutation_patch_disabled_exitcode(
            tmp::AbstractString,
            repo_root::AbstractString,
            source_relpath::AbstractString,
            patched::AbstractString;
            corpus::AbstractString,
            msg_needle::AbstractString,
            rule_id::AbstractString = "unsafe-boundary",
            config_toml::Union{Nothing, AbstractString} = nothing,
        )
        if config_toml !== nothing
            write(joinpath(tmp, ".AgentRuleLintConfig.toml"), config_toml)
        end
        write(joinpath(tmp, source_relpath), patched)
        script = _mutation_detector_script(tmp, corpus, msg_needle, rule_id)
        return _mutation_child_exitcode(tmp, script; dir = repo_root)
    end

    repo_root = dirname(@__DIR__)

    @testset "mutation child exit code contract" begin
        tmp = mktempdir()
        try
            cp(repo_root, tmp; force = true)
            crash = "throw(ArgumentError(\"mutation subprocess probe\"))"
            code = _mutation_child_exitcode(tmp, crash; dir = repo_root)
            @test code != 0
            @test code != _MUTATION_HITS_EXIT
        finally
            rm(tmp, recursive = true, force = true)
        end
    end

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
        root = mktempdir()
        try
            cp(repo_root, root; force = true)
            isfile(joinpath(root, ".AgentRuleLintConfig.toml")) &&
                rm(joinpath(root, ".AgentRuleLintConfig.toml"))
            for file in _UNSAFE_STRICT_POSITIVE
                @test isempty(_unsafe_hits(root, file))
                @test isempty(_unsafe_strict_hits(root, file))
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "strict preset macro corpus" begin
        root = mktempdir()
        try
            cp(repo_root, root; force = true)
            write(joinpath(root, ".AgentRuleLintConfig.toml"), _minimal_config_with_unsafe_strict())
            for file in _UNSAFE_STRICT_POSITIVE
                hits = _unsafe_hits(root, file)
                @test !isempty(hits)
            end
        finally
            rm(root, recursive = true, force = true)
        end
    end

    @testset "strict preset without rules.unsafe-boundary uses preset rule_id" begin
        root = mktempdir()
        try
            cp(repo_root, root; force = true)
            v = string(pkgversion(AgentRuleLint))
            write(
                joinpath(root, ".AgentRuleLintConfig.toml"),
                """
                agentrulelint_version = \"=$(v)\"
                default_format = \"human\"
                presets = [\"unsafe-boundary/strict\"]
                [rules.expect-audit]
                level = \"forbid\"
                on_allow_rule = \"warn\"
                [rules.\"unsafe-boundary/strict\"]
                level = \"deny\"
                """,
            )
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
        shared_tmp = mktempdir()
        cp(repo_root, shared_tmp; force = true)
        rule_rel = "src/rules/unsafe_boundary.jl"
        rule_path = joinpath(shared_tmp, rule_rel)
        config_path = joinpath(shared_tmp, ".AgentRuleLintConfig.toml")
        config_backup = isfile(config_path) ? read(config_path, String) : nothing

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

        try
            for (label, _, orig, pair, corpus, needle) in cases
                @testset "$label" begin
                    if label == "allow_modules gating"
                        cfg_root = mktempdir()
                        patched = replace(orig, pair)
                        allow_script = join(
                            [
                                "using AgentRuleLint",
                                "root = $(repr(cfg_root))",
                                "p = joinpath(root, \"test\", \"corpus\", \"unsafe_allow_module.jl\")",
                                "r = AgentRuleLint.check(root; paths=[p])",
                                "h = filter(d -> d.rule_id == \"unsafe-boundary\", r.violations)",
                                "exit(isempty(h) ? 0 : $(_MUTATION_HITS_EXIT))",
                            ],
                            '\n',
                        )
                        try
                            cp(repo_root, cfg_root; force = true)
                            write(
                                joinpath(cfg_root, ".AgentRuleLintConfig.toml"),
                                _minimal_config_with_unsafe("allow_modules = [\"BoundarySafe\"]\n"),
                            )
                            hits = filter(
                                d -> d.rule_id == "unsafe-boundary",
                                AgentRuleLint.check(
                                    cfg_root;
                                    paths = [joinpath("test", "corpus", "unsafe_allow_module.jl")],
                                ).violations,
                            )
                            @test isempty(hits)
                            write(rule_path, patched)
                            code = _mutation_child_exitcode(shared_tmp, allow_script; dir = repo_root)
                            @test code == _MUTATION_HITS_EXIT
                        finally
                            write(rule_path, unsafe_orig)
                            rm(cfg_root, recursive = true, force = true)
                        end
                    else
                        patched = replace(orig, pair)
                        strict = label == "macros"
                        rule_id = strict ? AgentRuleLint.UNSAFE_BOUNDARY_STRICT_PRESET_ID :
                            "unsafe-boundary"
                        strict_config = if strict
                            v = string(pkgversion(AgentRuleLint))
                            """
                            agentrulelint_version = \"=$(v)\"
                            default_format = \"human\"
                            presets = [\"unsafe-boundary/strict\"]
                            [rules.expect-audit]
                            level = \"forbid\"
                            on_allow_rule = \"warn\"
                            [rules.\"unsafe-boundary/strict\"]
                            level = \"deny\"
                            """
                        else
                            nothing
                        end
                        try
                            if strict
                                scratch = mktempdir()
                                try
                                    cp(repo_root, scratch; force = true)
                                    write(joinpath(scratch, ".AgentRuleLintConfig.toml"), strict_config)
                                    @test !isempty(_mutation_needle_hits(scratch, corpus, needle; rule_id))
                                finally
                                    rm(scratch, recursive = true, force = true)
                                end
                            else
                                @test !isempty(_mutation_needle_hits(repo_root, corpus, needle; rule_id))
                            end
                            code = _mutation_patch_disabled_exitcode(
                                shared_tmp,
                                repo_root,
                                rule_rel,
                                patched;
                                corpus = repr(corpus),
                                msg_needle = needle,
                                rule_id,
                                config_toml = strict_config,
                            )
                            @test code == 0
                        finally
                            write(rule_path, unsafe_orig)
                            if strict_config !== nothing
                                if config_backup === nothing
                                    isfile(config_path) && rm(config_path; force = true)
                                else
                                    write(config_path, config_backup)
                                end
                            end
                        end
                    end
                end
            end

            @testset "allow_globs gating" begin
                globs_root = mktempdir()
                patched = replace(
                    builtin_orig,
                    "path_matches_glob(fc.parsed.path, cfg.allow_globs) && return diags" =>
                        "false && return diags",
                )
                builtin_rel = "src/rules/builtin_rules.jl"
                builtin_path = joinpath(shared_tmp, builtin_rel)
                globs_script = join(
                    [
                        "using AgentRuleLint",
                        "r = AgentRuleLint.check($(repr(globs_root)); paths=[joinpath(\"test\", \"corpus\", \"unsafe_ccall.jl\")])",
                        "h = filter(d -> d.rule_id == \"unsafe-boundary\", r.violations)",
                        "exit(isempty(h) ? 0 : $(_MUTATION_HITS_EXIT))",
                    ],
                    '\n',
                )
                try
                    cp(repo_root, globs_root; force = true)
                    write(
                        joinpath(globs_root, ".AgentRuleLintConfig.toml"),
                        _minimal_config_with_unsafe("allow_globs = [\"**\"]\n"),
                    )
                    hits = filter(
                        d -> d.rule_id == "unsafe-boundary",
                        AgentRuleLint.check(
                            globs_root;
                            paths = [joinpath("test", "corpus", "unsafe_ccall.jl")],
                        ).violations,
                    )
                    @test isempty(hits)
                    write(builtin_path, patched)
                    code = _mutation_child_exitcode(shared_tmp, globs_script; dir = repo_root)
                    @test code == _MUTATION_HITS_EXIT
                finally
                    write(builtin_path, builtin_orig)
                    rm(globs_root, recursive = true, force = true)
                end
            end
        finally
            rm(shared_tmp, recursive = true, force = true)
        end

    end
end
