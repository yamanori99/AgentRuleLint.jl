function _effective_rule_level(policy::PolicyBundle, level::Symbol)
    if level == :allow
        return if policy.on_allow_rule == :error
            :forbid
        elseif policy.on_allow_rule == :warn
            :warn
        else
            :allow
        end
    end
    return level
end

function _push_builtin_violation!(
        diags::Vector{Violation},
        rule_id::String,
        origin::Symbol,
        eff_level::Symbol,
        path::String,
        source::AbstractString,
        byte_start::Int,
        byte_end::Int,
        msg::String,
        intent::String,
        do_not::String,
    )
    sp = span_from_byte_range(source, byte_start, byte_end)
    push!(
        diags,
        Violation(
            rule_id,
            origin,
            eff_level,
            path,
            sp,
            sp.start_line,
            "",
            :none,
            false,
            msg,
            intent,
            do_not,
        ),
    )
    return nothing
end

function run_builtin_rules(fc::FileContext, policy::PolicyBundle)
    diags = Violation[]
    julia_source_path(fc.parsed.path) || return diags
    ub = policy.unsafe_boundary
    if ub.active && !path_matches_glob(fc.parsed.path, ub.allow_globs)
        ub_eff = _effective_rule_level(policy, ub.level)
        if ub_eff != :allow
            append!(diags, diagnose_unsafe_boundary(fc, policy, ub_eff))
        end
    end
    ss = policy.shell_safety
    if ss.active
        ss_eff = _effective_rule_level(policy, ss.level)
        if ss_eff != :allow
            append!(diags, diagnose_shell_safety(fc, policy, ss_eff))
        end
    end
    return diags
end
