function _json_str(s::AbstractString)
    esc = replace(s, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t")
    return "\"" * esc * "\""
end

function _json_val(v)
    v isa Bool && return v ? "true" : "false"
    v isa Integer && return string(v)
    v isa AbstractFloat && return string(v)
    v isa AbstractString && return _json_str(v)
    v isa Symbol && return _json_str(String(v))
    v isa Dict && return "{" * join([_json_str(string(k)) * ":" * _json_val(val) for (k, val) in sort(collect(v); by = first)], ",") * "}"
    v isa AbstractVector && return "[" * join(_json_val.(v), ",") * "]"
    return _json_str(string(v))
end

function format_json(result::CheckResult)
    lines = String[]
    header = Dict{String, Any}(
        "type" => "header",
        "jailint_version" => string(pkgversion(JAILint)),
        "julia_version" => string(VERSION),
        "parser" => parser_rev_string(),
        "config_source" => config_source_dict(result.config_source),
        "position_encoding" => "utf8-codepoint-1based",
    )
    push!(lines, _json_val(header))
    for d in sort(result.violations; by = x -> (x.path, x.span, x.rule_id))
        rec = Dict{String, Any}(
            "type" => "diagnostic",
            "rule_id" => d.rule_id,
            "origin" => String(d.origin),
            "level" => String(d.level),
            "path" => d.path,
            "span" => Dict(
                "start_line" => d.span.start_line,
                "start_col" => d.span.start_col,
                "end_line" => d.span.end_line,
                "end_col" => d.span.end_col,
            ),
            "anchor_line" => d.anchor_line,
            "fingerprint" => d.fingerprint,
            "expect_status" => String(d.expect_status),
            "suppressed" => d.suppressed,
            "message" => d.message,
        )
        push!(lines, _json_val(rec))
    end
    summary = Dict{String, Any}(
        "type" => "summary",
        "complete" => result.complete,
        "violations" => result.violation_count,
        "suppressed" => result.suppressed_count,
        "rules" => length(unique(d.rule_id for d in result.violations)),
        "exit_code" => result.exit_code,
    )
    push!(lines, _json_val(summary))
    return join(lines, '\n') * '\n'
end
