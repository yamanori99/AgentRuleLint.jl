using AgentRuleLint
using Test

const RUNIC_ENV = joinpath(@__DIR__, "runic_env")
const ROOT = dirname(@__DIR__)

function runic_format_str(code::String)
    cmd = `julia --project=$RUNIC_ENV --startup-file=no -e 'using Runic; print(Runic.format_string(ARGS[1]))' $(code)`
    return String(read(cmd))
end

function diagnostic_signatures(result::CheckResult)
    return Set(
        (
            d.rule_id,
            d.anchor_line,
            String(d.expect_status),
            d.suppressed,
        ) for d in result.violations
    )
end

@testset "Runic invariance (corpus)" begin
    root = ROOT
    corpus_dir = joinpath(@__DIR__, "corpus")
    files = filter(f -> endswith(f, ".jl"), readdir(corpus_dir))
    @test !isempty(files)
    for f in files
        # syntax_error lives outside corpus (parse fail-closed fixture).
        src = read(joinpath(corpus_dir, f), String)
        formatted = runic_format_str(src)
        tmp = mktempdir()
        write(joinpath(tmp, f), src)
        write(joinpath(tmp, ".AgentRuleLintConfig.toml"), read(joinpath(root, ".AgentRuleLintConfig.toml"), String))
        before = AgentRuleLint.run_check(tmp; paths = [f]).violations
        write(joinpath(tmp, f), formatted)
        after = AgentRuleLint.run_check(tmp; paths = [f]).violations
        sig(v) =
            diagnostic_signatures(AgentRuleLint.CheckResult(v, true, 0, AgentRuleLint.ConfigSource(), :human, 20, 0, 0))
        @test sig(before) == sig(after)
    end
end