@testset "whitespace gate script" begin
    _gate_script = joinpath(ROOT, "scripts", "whitespace-gate.sh")

    function _run_gate(repo::AbstractString; diff_range = nothing)
        repo = abspath(String(repo))
        cmd = `bash $(_gate_script)`
        if diff_range === nothing
            return withenv("WHITESPACE_GATE_REPO" => repo) do
                run(ignorestatus(setenv(cmd; dir = repo)))
            end
        end
        return withenv(
            "WHITESPACE_GATE_REPO" => repo,
            "WHITESPACE_GATE_DIFF_RANGE" => String(diff_range),
        ) do
            run(ignorestatus(setenv(cmd; dir = repo)))
        end
    end

    function _gate_repo()
        dir = mktempdir()
        init_git_repo!(dir)
        return dir
    end

    function _write_tracked!(repo::AbstractString, rel::AbstractString, bytes::AbstractVector{UInt8})
        path = joinpath(repo, rel)
        mkpath(dirname(path))
        open(path, "w") do io
            write(io, bytes)
        end
        git_commit_all!(repo, "add $(rel)")
        return nothing
    end

    @testset "trailing newline fixtures" begin
        @testset "missing final newline fails" begin
            repo = _gate_repo()
            try
                _write_tracked!(repo, "a.txt", b"hi")
                proc = _run_gate(repo)
                @test proc.exitcode == 1
            finally
                rm(repo; force = true, recursive = true)
            end
        end

        @testset "two trailing newlines fail" begin
            repo = _gate_repo()
            try
                _write_tracked!(repo, "b.txt", b"ok\n\n")
                proc = _run_gate(repo)
                @test proc.exitcode == 1
            finally
                rm(repo; force = true, recursive = true)
            end
        end

        @testset "exactly one trailing newline passes" begin
            repo = _gate_repo()
            try
                _write_tracked!(repo, "c.txt", b"ok\n")
                proc = _run_gate(repo)
                @test proc.exitcode == 0
            finally
                rm(repo; force = true, recursive = true)
            end
        end

        @testset "binary without newline passes" begin
            repo = _gate_repo()
            try
                _write_tracked!(repo, "bin.dat", UInt8[0x00, 0x01, 0x02])
                proc = _run_gate(repo)
                @test proc.exitcode == 0
            finally
                rm(repo; force = true, recursive = true)
            end
        end
    end

    @testset "git diff --check trailing whitespace" begin
        repo = _gate_repo()
        try
            _write_tracked!(repo, "clean.txt", b"x\n")
            path = joinpath(repo, "clean.txt")
            open(path, "w") do io
                write(io, "line \n")
            end
            run_git_cmd(repo, "add", "clean.txt"; cwd = repo)
            run_git_cmd(
                repo,
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-q",
                "-m",
                "trailing space";
                cwd = repo,
            )
            base = strip(git_read(repo, "rev-parse", "HEAD~1"))
            proc = _run_gate(repo; diff_range = "$(base)..HEAD")
            @test proc.exitcode != 0
        finally
            rm(repo; force = true, recursive = true)
        end
    end

    @testset "repository tree passes when clean" begin
        fetch_ok = false
        try
            run_git_cmd(ROOT, "fetch", "origin", "main", "--no-tags"; cwd = ROOT)
            fetch_ok = true
        catch
        end
        base = if fetch_ok
            try
                strip(String(read_git_cmd(ROOT, "merge-base", "origin/main", "HEAD"; error_prefix = "test git failed")))
            catch
                strip(String(read_git_cmd(ROOT, "rev-parse", "HEAD~1")))
            end
        else
            strip(String(read_git_cmd(ROOT, "rev-parse", "HEAD~1")))
        end
        proc = _run_gate(ROOT; diff_range = "$(base)..HEAD")
        @test proc.exitcode == 0
    end
end