@testset "GitHub Actions log groups" begin
    isdefined(@__MODULE__, :github_actions_log_groups_enabled) ||
        include(joinpath(@__DIR__, "github_actions_log.jl"))
    isdefined(@__MODULE__, :print_mutation_report) ||
        include(joinpath(@__DIR__, "mutation", "run_all_lib.jl"))

    function capture_stdio(f)
        out_path = tempname()
        err_path = tempname()
        open(out_path, "w") do out_io
            open(err_path, "w") do err_io
                redirect_stdout(out_io) do
                    redirect_stderr(err_io) do
                        f()
                    end
                end
            end
        end
        out = isfile(out_path) ? read(out_path, String) : ""
        err = isfile(err_path) ? read(err_path, String) : ""
        rm(out_path, force = true)
        rm(err_path, force = true)
        return out, err
    end

    function count_groups(s::AbstractString)
        return count("::group::", s), count("::endgroup::", s)
    end

    @testset "disabled outside GITHUB_ACTIONS" begin
        withenv("GITHUB_ACTIONS" => nothing) do
            @test !github_actions_log_groups_enabled()
            stdout, _ = capture_stdio() do
                github_actions_group_begin(Base.stdout, "title")
                github_actions_group_end(Base.stdout)
            end
            @test stdout == ""
            results = [
                (
                    name = "ok.jl",
                    result = :pass,
                    code = 0,
                    termsignal = 0,
                    elapsed = 0.1,
                    stdout = "hello\n",
                    stderr = "",
                ),
            ]
            out, err = capture_stdio() do
                print_mutation_report(results)
            end
            @test !occursin("::group::", out)
            @test !occursin("::group::", err)
            @test occursin("PASS", out)
        end
    end

    @testset "mutation harness groups balanced when enabled" begin
        withenv("GITHUB_ACTIONS" => "true") do
            results = [
                (
                    name = "a.jl",
                    result = :pass,
                    code = 0,
                    termsignal = 0,
                    elapsed = 0.2,
                    stdout = "alpha\n",
                    stderr = "",
                ),
                (
                    name = "b.jl",
                    result = :fail,
                    code = 1,
                    termsignal = 0,
                    elapsed = 0.3,
                    stdout = "",
                    stderr = "oops\n",
                ),
            ]
            out, err = capture_stdio() do
                @test print_mutation_report(results) == 1
            end
            g, e = count_groups(out)
            @test g == e == 1
            @test occursin("::group::a.jl", out)
            @test !occursin("::group::b.jl", out)
            @test occursin("oops", err)
            @test occursin("FAIL", out)
            summary_idx = findfirst("b.jl", out)
            @test summary_idx !== nothing
            group_end = findlast("::endgroup::", out)
            @test group_end !== nothing
            @test group_end < summary_idx
        end
    end

    @testset "Pkg.test output wrapper groups passing captured output only" begin
        withenv("GITHUB_ACTIONS" => "true") do
            buf = IOBuffer()
            log_io = GitHubActionsTestLogIO(buf)
            write(
                log_io,
                "Output generated during execution of 'test_foo':\n┌ line\n└ line\n",
            )
            flush(log_io)
            s = String(take!(buf))
            g, e = count_groups(s)
            @test g == e == 1
            @test occursin("::group::test_foo", s)
            @test !occursin("::group::", split(s, "::group::")[1])
        end
        withenv("GITHUB_ACTIONS" => "true") do
            buf = IOBuffer()
            log_io = GitHubActionsTestLogIO(buf)
            fail_header = "Output generated during execution of '\e[31mtest_fail\e[39m':\n┌ err\n└ err\n"
            write(log_io, fail_header)
            flush(log_io)
            s = String(take!(buf))
            @test !occursin("::group::", s)
            @test occursin("err", s)
        end
        withenv("GITHUB_ACTIONS" => nothing) do
            buf = IOBuffer()
            log_io = GitHubActionsTestLogIO(buf)
            write(log_io, "Output generated during execution of 'test_foo':\n┌ line\n└ line\n")
            flush(log_io)
            s = String(take!(buf))
            @test s == "Output generated during execution of 'test_foo':\n┌ line\n└ line\n"
        end
    end

    @testset "mutation summary line stays outside groups" begin
        dir = mktempdir()
        try
            write(joinpath(dir, "one.jl"), "exit(0)\n")
            out, _ = capture_stdio() do
                withenv("GITHUB_ACTIONS" => "true") do
                    @test mutation_run_all_main(dir) == 0
                end
            end
            g, e = count_groups(out)
            @test g == e
            @test findfirst("mutation run_all: done", out) !== nothing
            last_end = findlast("::endgroup::", out)
            done_idx = findfirst("mutation run_all: done", out)
            if e > 0
                @test last_end !== nothing && last_end < done_idx
            end
        finally
            rm(dir, recursive = true, force = true)
        end
    end
end
