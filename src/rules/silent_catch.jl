const SILENT_CATCH_ID = "silent-catch"

function _silent_catch_warn_counts(rule::RuleSpec)
    v = get(rule.extra, :warn_counts_as_handling, "false")
    return lowercase(strip(v)) in ("true", "1", "yes")
end

function _push_silent_catch_violation!(
        diags::Vector{Violation},
        rule::RuleSpec,
        path::String,
        source::AbstractString,
        site::TryCatchSite,
        msg::String,
    )
    _, sp = span_for_line(source, site.try_line)
    push!(
        diags,
        Violation(
            SILENT_CATCH_ID,
            rule.origin,
            rule.level,
            path,
            sp,
            site.try_line,
            "",
            :none,
            false,
            msg,
            rule.intent,
            rule.do_not,
        ),
    )
    return nothing
end

function run_silent_catch(fc::FileContext, policy::PolicyBundle)
    rule = get(policy.rules, SILENT_CATCH_ID, nothing)
    rule === nothing && return Violation[]
    rule.level == :allow && return Violation[]
    path = fc.parsed.path
    source = fc.parsed.normalized
    tree = parse_source(source; filename = path)
    warn_counts = _silent_catch_warn_counts(rule)
    diags = Violation[]
    for site in collect_try_catch_sites(tree, source)
        body = site.catch_body
        body === nothing && continue
        swallows = catch_swallows_exception(
            body,
            site.catch_body_pos,
            source,
            site.catch_var;
            warn_counts_as_handling = warn_counts,
        )
        swallows || continue
        dodge = catch_var_dodge_name(site.catch_var)
        msg = dodge ?
            "catch binding uses a leading-underscore name but does not rethrow or throw" :
            "catch block swallows exceptions without rethrow or throw on unhandled paths"
        _push_silent_catch_violation!(diags, rule, path, source, site, msg)
    end
    return diags
end
