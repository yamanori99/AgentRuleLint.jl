include("mutation_lib.jl")

const _PROBE = raw"""
function _mutable_globals_mutation_probe()
    RULE_TABLE_KEYS[] = nothing
end
"""

run_source_mutation(;
    name = "no_mutable_globals []= guard",
    rel_path = "test/test_no_mutable_globals.jl",
    needle = raw"\\[\\]\\s*=",
    replacement = raw"\\[\\]\\s*\\z",
    verify = root -> begin
        test_rel = joinpath(root, "test", "test_no_mutable_globals.jl")
        regex_mutated = occursin(raw"\\[\\]\\s*\\z", read(test_rel, String))
        if regex_mutated
            p = joinpath(root, "src", "AgentRuleLint.jl")
            write(p, read(p, String) * "\n" * _PROBE)
        end
        script = join(
            [
                "using Test",
                "const ROOT = $(repr(root))",
                "try",
                "    include(joinpath(ROOT, \"test\", \"test_no_mutable_globals.jl\"))",
                "catch err",
                "    if err isa LoadError",
                "        inner = err.error",
                "        if inner isa ErrorException && occursin(\"runtime mutation\", inner.msg)",
                "            exit(0)",
                "        end",
                "    end",
                "    rethrow(err)",
                "end",
                "exit($(regex_mutated ? 2 : 0))",
            ],
            '\n',
        )
        cmd = _julia_project_cmd(root, "-e", script)
        return detector_disabled(cmd; dir = root)
    end,
)
