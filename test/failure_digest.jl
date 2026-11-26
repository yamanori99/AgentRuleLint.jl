# End-of-suite failure digest for agents: walk Test stdlib results (not stdout).
# Does not record additional tests or change pass/fail/error counts.

const FAILURE_DIGEST_MARKER = "=== AgentRuleLint test failure digest ==="
const FAILURE_DIGEST_MAX = 50
const FAILURE_DIGEST_PATH = joinpath(ROOT, "test", "last_failures.txt")

# Test-only: when set, invoked at the start of `format_failure_digest` (see test_failure_digest.jl).
const _FAILURE_DIGEST_FORMAT_HOOK = Ref{Union{Nothing, Function}}(nothing)

struct FailureDigestEntry
    kind::String
    testset_path::String
    location::String
    message::String
end

function _digest_first_line(s::AbstractString)
    stripped = strip(s)
    isempty(stripped) && return ""
    nl = findfirst('\n', stripped)
    nl === nothing && return String(stripped)
    return String(strip(SubString(stripped, 1, prevind(stripped, nl))))
end

function _digest_rel_file(file, root::AbstractString)
    f = String(something(file, "none"))
    isempty(f) && return "none"
    ap = isabspath(f) ? f : abspath(root, f)
    root_abs = abspath(root)
    startswith(ap, root_abs) || return f
    return replace(normpath(relpath(ap, root_abs)), '\\' => '/')
end

function _digest_location(src::LineNumberNode, root::AbstractString)
    return string(_digest_rel_file(src.file, root), ":", src.line)
end

function _digest_fail_message(t::Test.Fail)
    if t.data !== nothing && !isempty(t.data)
        return _digest_first_line(t.data)
    end
    return _digest_first_line(t.orig_expr)
end

function _digest_error_message(t::Test.Error)
    isempty(t.value) || return _digest_first_line(t.value)
    return _digest_first_line(t.orig_expr)
end

function _digest_results_snapshot(ts::Test.AbstractTestSet)
    ts isa Test.DefaultTestSet && return @lock ts.results_lock copy(ts.results)
    return collect(Test.results(ts))
end

function collect_failure_digest_entries!(
        out::Vector{FailureDigestEntry},
        ts::Test.AbstractTestSet,
        prefix::Vector{String},
        root::AbstractString,
    )
    desc = String(strip(String(ts.description)))
    path_parts = isempty(desc) ? prefix : String[prefix; desc]
    for t in _digest_results_snapshot(ts)
        if t isa Test.AbstractTestSet
            collect_failure_digest_entries!(out, t, path_parts, root)
        elseif t isa Test.Fail
            push!(
                out,
                FailureDigestEntry(
                    "FAIL",
                    join(path_parts, " / "),
                    _digest_location(t.source, root),
                    _digest_fail_message(t),
                ),
            )
        elseif t isa Test.Error
            t.test_type === :test_interrupted && continue
            push!(
                out,
                FailureDigestEntry(
                    "ERROR",
                    join(path_parts, " / "),
                    _digest_location(t.source, root),
                    _digest_error_message(t),
                ),
            )
        end
    end
    return out
end

function _digest_exception_first_line(err)
    return _digest_first_line(sprint(showerror, err))
end

function format_digest_unavailable(err)
    io = IOBuffer()
    println(io, FAILURE_DIGEST_MARKER)
    println(io, "digest unavailable: ", _digest_exception_first_line(err))
    return String(take!(io))
end

function format_failure_digest(
        ts::Test.AbstractTestSet;
        root::AbstractString = ROOT,
        max_entries::Int = FAILURE_DIGEST_MAX,
    )
    hook = _FAILURE_DIGEST_FORMAT_HOOK[]
    hook !== nothing && hook()
    entries = FailureDigestEntry[]
    collect_failure_digest_entries!(entries, ts, String[], root)
    io = IOBuffer()
    println(io, FAILURE_DIGEST_MARKER)
    if isempty(entries)
        println(io, "no failures")
        return String(take!(io))
    end
    cap = max(0, max_entries)
    shown = min(length(entries), cap)
    for i in 1:shown
        e = entries[i]
        println(io, e.kind, "  ", e.testset_path, "  ", e.location, "  ", e.message)
    end
    rest = length(entries) - shown
    rest > 0 && println(io, "... and ", rest, " more (", shown, " shown)")
    return String(take!(io))
end

function emit_failure_digest(
        ts::Test.AbstractTestSet;
        root::AbstractString = ROOT,
        path::AbstractString = FAILURE_DIGEST_PATH,
    )
    try
        text = format_failure_digest(ts; root = root)
        print(text)
        write(path, text)
    catch err
        err isa InterruptException && rethrow()
        text = format_digest_unavailable(err)
        print(text)
        try
            write(path, text)
        catch write_err
            write_err isa InterruptException && rethrow()
            println(
                "failure digest: could not write ",
                path,
                ": ",
                _digest_exception_first_line(write_err),
            )
        end
    end
    return nothing
end
