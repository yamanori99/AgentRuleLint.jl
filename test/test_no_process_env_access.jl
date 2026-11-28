# Guard: `src/` must not read process environment / host probes except allowlisted (issue #155 Part 1).
# Syntax scan via AgentRuleLint.parse_source (SyntaxAdapter boundary).

const _SRC_ROOT = joinpath(ROOT, "src")
const _PROBE_REL = "src/__env_guard_probe__.jl"

const _ENV_ACCESS_ALLOWLIST = [
    # (relpath under repo, construct id, reason) — allowlisted uses in src/git.jl only
    ("src/git.jl", :setenv, "Attach merged isolated env to bundled git Cmd; run and probe git"),
]

const _FORBIDDEN_CALL_CALLEE = Dict{String, Symbol}(
    "getenv" => :getenv,
    "hasenv" => :hasenv,
    "withenv" => :withenv,
    "addenv" => :addenv,
    "setenv" => :setenv,
    "homedir" => :homedir,
    "time" => :time,
    "time_ns" => :time_ns,
    "now" => :now,
    "rand" => :rand,
    "randn" => :randn,
    "randstring" => :randstring,
    "gethostname" => :gethostname,
    "getpid" => :getpid,
    "Sys.which" => :Sys_which,
    "Dates.now" => :Dates_now,
    "Threads.nthreads" => :Threads_nthreads,
)

const _FORBIDDEN_QUALIFIED_IDENTS = Dict{String, Symbol}(
    "Sys.CPU_THREADS" => :Sys_CPU_THREADS,
)

function _src_julia_files(dir::AbstractString)
    out = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(f, ".jl") || continue
            push!(out, joinpath(root, f))
        end
    end
    return sort(out)
end

function _allowlisted(rel_path::AbstractString, construct::Symbol)
    for (file, id, _) in _ENV_ACCESS_ALLOWLIST
        file == rel_path && id == construct && return true
    end
    return false
end

function _qualified_name(node, src::AbstractString, pos::Int)
    if AgentRuleLint.syntax_kind(node) == AgentRuleLint.KIdentifier
        return AgentRuleLint._node_text_trim(node, src, pos)
    elseif AgentRuleLint.syntax_kind(node) == AgentRuleLint.KDot
        parts = String[]
        for (c, cp) in AgentRuleLint._child_positions(node, pos)[1]
            AgentRuleLint.syntax_is_trivia(c) && continue
            AgentRuleLint.syntax_kind(c) == AgentRuleLint.KIdentifier &&
                push!(parts, AgentRuleLint._node_text_trim(c, src, cp))
        end
        return join(parts, ".")
    end
    return ""
end

function _call_callee_qualified(node, src::AbstractString, pos::Int)
    AgentRuleLint.syntax_kind(node) == AgentRuleLint.KCall || return ""
    for (c, cp) in AgentRuleLint._child_positions(node, pos)[1]
        AgentRuleLint.syntax_is_trivia(c) && continue
        k = AgentRuleLint.syntax_kind(c)
        if k == AgentRuleLint.KIdentifier
            return AgentRuleLint._node_text_trim(c, src, cp)
        elseif k == AgentRuleLint.KDot
            return _qualified_name(c, src, cp)
        end
        break
    end
    return ""
end

function _snippet_at(src::AbstractString, pos::Int, node)
    sp = AgentRuleLint.syntax_span(node)
    stop = min(pos + sp - 1, ncodeunits(src))
    pos > stop && return ""
    return strip(String(src[pos:stop]))
end

function _record_usage!(
        used::Set{Tuple{String, Symbol}},
        rel::AbstractString,
        construct::Symbol,
        violations,
        line::Int,
        snippet::AbstractString,
    )
    push!(used, (String(rel), construct))
    _allowlisted(rel, construct) && return
    push!(violations, (String(rel), line, construct, String(snippet)))
    return
end

function _walk_env_guard!(
        node,
        pos::Int,
        src::AbstractString,
        rel::AbstractString,
        violations,
        used::Set{Tuple{String, Symbol}},
    )
    if AgentRuleLint.syntax_is_trivia(node)
        return
    end
    k = AgentRuleLint.syntax_kind(node)
    if string(k) == "Comment"
        return
    end
    if k == AgentRuleLint.KStringExpr || k == AgentRuleLint.KCharExpr
        AgentRuleLint._string_node_interpolated(node, pos) || return
    end

    line = AgentRuleLint.line_number_at_byte(src, pos)

    if k == AgentRuleLint.KIdentifier
        name = AgentRuleLint._node_text_trim(node, src, pos)
        if name == "ENV"
            _record_usage!(used, rel, :ENV, violations, line, _snippet_at(src, pos, node))
        end
    elseif k == AgentRuleLint.KDot
        qn = _qualified_name(node, src, pos)
        id = get(_FORBIDDEN_QUALIFIED_IDENTS, qn, nothing)
        id !== nothing &&
            _record_usage!(used, rel, id, violations, line, _snippet_at(src, pos, node))
    elseif k == AgentRuleLint.KCall
        callee = _call_callee_qualified(node, src, pos)
        id = get(_FORBIDDEN_CALL_CALLEE, callee, nothing)
        id !== nothing &&
            _record_usage!(used, rel, id, violations, line, _snippet_at(src, pos, node))
    end

    for (c, cp) in AgentRuleLint._child_positions(node, pos)[1]
        _walk_env_guard!(c, cp, src, rel, violations, used)
    end
    return
end

function _scan_env_guard_source(rel::AbstractString, source::AbstractString)
    src = AgentRuleLint.normalize_source(source)
    tree = AgentRuleLint.parse_source(src; filename = rel)
    violations = Tuple{String, Int, Symbol, String}[]
    used = Set{Tuple{String, Symbol}}()
    _walk_env_guard!(tree, 1, src, rel, violations, used)
    return violations, used
end

function collect_src_process_env_violations(repo_root::AbstractString)
    src = joinpath(repo_root, "src")
    violations = Tuple{String, Int, Symbol, String}[]
    used = Set{Tuple{String, Symbol}}()
    for path in _src_julia_files(src)
        rel = replace(relpath(path, repo_root), '\\' => '/')
        text = read(path, String)
        v, u = _scan_env_guard_source(rel, text)
        append!(violations, v)
        union!(used, u)
    end
    return violations
end

function _collect_src_env_guard_used(repo_root::AbstractString)
    combined = Set{Tuple{String, Symbol}}()
    src = joinpath(repo_root, "src")
    for path in _src_julia_files(src)
        rel = replace(relpath(path, repo_root), '\\' => '/')
        _, u = _scan_env_guard_source(rel, read(path, String))
        union!(combined, u)
    end
    return combined
end

function _run_env_guard_tests()
    @testset "src/ process-environment access guard" begin
        @testset "docstrings and comments are not matches (width.jl ENV mention)" begin
            doc = read(joinpath(ROOT, "src", "format", "width.jl"), String)
            @test occursin("ENV[\"COLUMNS\"]", doc)
            v = collect_src_process_env_violations(ROOT)
            @test isempty(filter(x -> x[1] == "src/format/width.jl", v))
        end

        @testset "syntax scan evasions (probe sources)" begin
            cases = [
                ("getindex(ENV, \"k\")", :ENV, 1),
                ("get!(ENV, \"k\", \"d\")", :ENV, 1),
                ("Dict(ENV)", :ENV, 1),
                ("collect(ENV)", :ENV, 1),
                ("merge(Dict{String,String}(), ENV)", :ENV, 1),
                ("const E = ENV", :ENV, 1),
                ("""get(ENV, "A", ""); s = \"\"\"doc\"\"\"""", :ENV, 1),
                ("gethostname()", :gethostname, 1),
            ]
            for (src, want, line) in cases
                v, _ = _scan_env_guard_source(_PROBE_REL, src * "\n")
                hit = filter(x -> x[2] == line && x[3] == want, v)
                isempty(hit) &&
                    error("expected construct $want at line $line for probe:\n$src\nfound: $v")
                @test !isempty(hit)
            end
            comment_only = "# getenv(\"X\")\n"
            v, _ = _scan_env_guard_source(_PROBE_REL, comment_only)
            @test isempty(v)
        end

        violations = collect_src_process_env_violations(ROOT)
        for (file, line, construct, snippet) in violations
            @error "process-environment access outside allowlist" file line construct snippet
        end
        @test isempty(violations)

        used = _collect_src_env_guard_used(ROOT)
        stale = [(f, id) for (f, id, _) in _ENV_ACCESS_ALLOWLIST if (f, id) ∉ used]
        @test isempty(stale) || error(
            "allowlist entries with no use in src/: $(join(["$f:$id" for (f, id) in stale], ", "))",
        )
    end
    return nothing
end

get(ENV, "AGENTRULELINT_ENV_GUARD_PROBE", "") == "1" || _run_env_guard_tests()
