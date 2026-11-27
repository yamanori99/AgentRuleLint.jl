function _git_porcelain_status_line_path(line::AbstractString)
    line = strip(String(line))
    length(line) < 4 && return line
    rest = strip(line[4:end])
    if occursin(" -> ", rest)
        parts = split(rest, " -> "; limit = 2)
        return strip(String(parts[end]))
    end
    return rest
end

function _suite_git_status_allowed(rel_path::AbstractString)
    rel = replace(strip(String(rel_path)), '\\' => '/')
    for allowed in SUITE_GIT_STATUS_EXCLUSIONS
        allowed == rel && return true
    end
    return false
end

function _filter_disallowed_git_status(status::AbstractString)
    violations = String[]
    for line in eachline(IOBuffer(status); keep = false)
        isempty(strip(line)) && continue
        path = _git_porcelain_status_line_path(line)
        _suite_git_status_allowed(path) || push!(violations, line)
    end
    return violations
end

@testset "repository tree untouched by tests" begin
    status = read(`git -C $(ROOT) status --porcelain --untracked-files=all`, String)
    violations = _filter_disallowed_git_status(status)
    @test isempty(violations)
    if !isempty(violations)
        for v in violations
            @error "unexpected change after test suite" v
        end
    end
end

@testset "src/ untouched by tests" begin
    status = read(`git -C $(ROOT) status --porcelain -- src`, String)
    @test isempty(strip(status))
end