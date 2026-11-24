using JAILint
using Test

const RUNIC_ENV = joinpath(@__DIR__, "runic_env")

function runic_format_str(code::String)
    cmd = `julia --project=$RUNIC_ENV --startup-file=no -e 'using Runic; print(Runic.format_str(ARGS[1]))' $(code)`
    return String(read(cmd))
end

function diagnostic_signatures(result::CheckResult)
    return Set(
        (
            d.rule_id,
            d.anchor_line,
            String(d.expect_status),
            d.suppressed,
        ) for d in result.diagnostics
    )
end

@testset "Runic invariance (corpus)" begin
    if !isfile(joinpath(RUNIC_ENV, "Manifest.toml"))
        run(`julia --project=$RUNIC_ENV -e 'using Pkg; Pkg.add("Runic")'`)
    end
    root = dirname(@__DIR__)
    corpus_dir = joinpath(@__DIR__, "corpus")
    for f in readdir(corpus_dir)
        endswith(f, ".jl") || continue
        path = joinpath("test", "corpus", f)
        src = read(joinpath(corpus_dir, f), String)
        formatted = runic_format_str(src)
        tmp = mktempdir()
        write(joinpath(tmp, f), src)
        write(joinpath(tmp, ".JAILintConfig.toml"), read(joinpath(root, ".JAILintConfig.toml"), String))
        before = run_check(tmp; paths = [f]).diagnostics
        write(joinpath(tmp, f), formatted)
        after = run_check(tmp; paths = [f]).diagnostics
        sig(v) = diagnostic_signatures(CheckResult(v, true, 0, Dict(), 0, 0))
        @test sig(before) == sig(after)
    end
end
