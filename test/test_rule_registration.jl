@testset "rule registration completeness" begin
    rules_dir = joinpath(ROOT, "src", "rules")
    test_dir = joinpath(ROOT, "test")

    @testset "RULE_DEFS sorted and unique" begin
        ids = [d.id for d in AgentRuleLint.RULE_DEFS]
        @test ids == sort(ids)
        @test length(ids) == length(unique(ids))
        @test length(AgentRuleLint.RULE_DEFS) == 10
    end

    @testset "every RuleDef has source, test, and coverage" begin
        for def in AgentRuleLint.RULE_DEFS
            src = joinpath(rules_dir, def.source_file)
            @test isfile(src)
            @test def.source_file == basename(def.source_file)
            @test occursin(r"^[a-z0-9_]+\.jl$", def.source_file)

            tf = joinpath(test_dir, def.test_file)
            @test isfile(tf)
            @test def.test_file == basename(def.test_file)

            @test !isempty(def.coverage_paths)
            for rel in def.coverage_paths
                @test isfile(joinpath(ROOT, rel))
            end
        end
    end

    @testset "every rule source file with RuleDef is registered" begin
        # Non-rule modules under src/rules/ (no RuleDef const).
        infrastructure = Set(
            [
                "builtin_rules.jl",
                "common.jl",
                "project_rules.jl",
                "registry.jl",
            ]
        )
        registered_sources = Set(d.source_file for d in AgentRuleLint.RULE_DEFS)
        for name in readdir(rules_dir)
            endswith(name, ".jl") || continue
            name in infrastructure && continue
            path = joinpath(rules_dir, name)
            text = read(path, String)
            if occursin(r"\bRuleDef\s*\(", text)
                @test name in registered_sources
            end
        end
        for name in registered_sources
            @test name ∉ infrastructure
            @test isfile(joinpath(rules_dir, name))
        end
    end

    @testset "init_registry covers RuleDef ids when active" begin
        pol = AgentRuleLint.default_policy(ROOT)
        AgentRuleLint.init_registry!(pol)
        for id in (
                "analysis-incomplete",
                "expect-audit",
                "silent-catch",
                "manifest-sync",
                "protected-paths",
                "ceiling-ratchet",
            )
            @test haskey(AgentRuleLint.BUILTIN_RULES, id)
        end
        @test haskey(AgentRuleLint.RULE_DEFS_BY_ID, "shell-safety/process-pattern")
        @test haskey(AgentRuleLint.RULE_DEFS_BY_ID, "unsafe-boundary")
        @test haskey(AgentRuleLint.RULE_DEFS_BY_ID, "test-integrity")
        @test haskey(AgentRuleLint.RULE_DEFS_BY_ID, "scope-paths")
        @test haskey(AgentRuleLint.RULE_DEFS_BY_ID, "analysis-incomplete")
    end
end
