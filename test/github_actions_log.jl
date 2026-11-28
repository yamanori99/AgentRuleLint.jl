# GitHub Actions workflow commands for collapsible log sections (display only).

"""True only on GitHub Actions runners (`GITHUB_ACTIONS=true`)."""
function github_actions_log_groups_enabled()
    return get(ENV, "GITHUB_ACTIONS", "") == "true"
end

function github_actions_group_begin(io::IO, title::AbstractString)
    github_actions_log_groups_enabled() || return
    println(io, "::group::", title)
    return nothing
end

function github_actions_group_end(io::IO)
    github_actions_log_groups_enabled() || return
    println(io, "::endgroup::")
    return nothing
end

const _PTR_OUTPUT_HEADER = r"Output generated during execution of '([^']+)'"

function _strip_ansi(s::AbstractString)
    return replace(String(s), r"\e\[[0-9;]*m" => "")
end

function _parse_parallel_test_output_header(line::AbstractString)
    m = match(_PTR_OUTPUT_HEADER, line)
    m === nothing && return nothing
    cap = m.captures[1]
    cap === nothing && return nothing
    return _strip_ansi(String(cap))
end

function _parallel_test_output_header_failed(line::AbstractString)
    return occursin("ptr_error", line) || occursin("\e[31m", line)
end

struct GitHubActionsTestLogIO{T<:IO} <: IO
    inner::T
    buf::IOBuffer
    group_open::Base.RefValue{Bool}
end

GitHubActionsTestLogIO(io::IO) = GitHubActionsTestLogIO{typeof(io)}(io, IOBuffer(), Base.Ref(false))

function _gha_test_log_flush_line!(wr::GitHubActionsTestLogIO, line::AbstractString)
    stripped = chomp(line)
    if wr.group_open[] && startswith(stripped, "Test Summary:")
        github_actions_group_end(wr.inner)
        wr.group_open[] = false
    end
    if !wr.group_open[]
        title = _parse_parallel_test_output_header(stripped)
        if title !== nothing && !_parallel_test_output_header_failed(stripped)
            github_actions_group_begin(wr.inner, title)
            wr.group_open[] = true
        end
    end
    print(wr.inner, line)
    if wr.group_open[] && (startswith(stripped, "└") || startswith(stripped, "["))
        github_actions_group_end(wr.inner)
        wr.group_open[] = false
    end
    return nothing
end

function _gha_test_log_drain_lines!(wr::GitHubActionsTestLogIO)
    data = String(take!(wr.buf))
    isempty(data) && return
    start = firstindex(data)
    while true
        nl = findnext('\n', data, start)
        if nl === nothing
            write(wr.buf, data[start:end])
            break
        end
        _gha_test_log_flush_line!(wr, data[start:nl])
        start = nl + 1
        start > lastindex(data) && break
    end
    return nothing
end

function Base.flush(wr::GitHubActionsTestLogIO)
    _gha_test_log_drain_lines!(wr)
    flush(wr.inner)
    return nothing
end

function Base.unsafe_write(wr::GitHubActionsTestLogIO, p::Ptr{UInt8}, nb::UInt)
    nb == 0 && return 0
    data = unsafe_wrap(Vector{UInt8}, p, Int(nb))
    write(wr.buf, data)
    _gha_test_log_drain_lines!(wr)
    return Int(nb)
end

function Base.unsafe_read(::GitHubActionsTestLogIO, ::Ptr{UInt8}, ::UInt)
    return 0
end

function Base.eof(wr::GitHubActionsTestLogIO)
    return eof(wr.inner) && position(wr.buf) == 0
end

function Base.close(wr::GitHubActionsTestLogIO)
    flush(wr)
    return nothing
end
