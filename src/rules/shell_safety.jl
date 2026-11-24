const _SHELL_SAFETY_INTENT =
    "Reject hazardous process patterns in statically known shell/Cmd literals (pkill, killall, remote shells, sudo)."
const _SHELL_SAFETY_DO_NOT =
    "Split command names (\"pk\" * \"ill\"), alias binaries, or build Cmd from runtime values to evade folding."

const _SHELL_HAZARD_PATTERNS = [
    (r"\bpkill\b", "pkill"),
    (r"\bkillall\b", "killall"),
    (r"\bssh\b.*\s--\s", "ssh --"),
    (r"\bsudo\b", "sudo"),
]

"""True when a dashed shell option carries `-c` (e.g. `-c`, `-lc`, `-cl`, `-ec`)."""
function _option_includes_dash_c(opt::AbstractString)
    startswith(opt, "-") || return false
    opt == "-c" && return true
    return length(opt) > 2 && occursin('c', opt[2:end])
end

function _shell_dash_c_label(cmd::AbstractString)
    tokens = split(cmd; limit = 0)
    for i in 1:(length(tokens) - 1)
        shell = tokens[i]
        shell in ("sh", "bash") || continue
        if tokens[i + 1] == "-c" || _option_includes_dash_c(tokens[i + 1])
            return "$(shell) -c"
        end
    end
    return occursin(r"\bsh\b\s+-c", cmd) ? "sh -c" :
        occursin(r"\bbash\b\s+-c", cmd) ? "bash -c" : nothing
end

function _cmd_argv_hazard(cmd::AbstractString)
    dash = _shell_dash_c_label(cmd)
    dash !== nothing && return dash
    for (rx, label) in _SHELL_HAZARD_PATTERNS
        occursin(rx, cmd) && return label
    end
    return nothing
end

function diagnose_shell_safety(fc::FileContext, policy::PolicyBundle, eff_level::Symbol)
    source = fc.parsed.normalized
    tree = parse_source(source; filename = fc.parsed.path)
    literals = collect_cmd_string_literals(tree, source)
    cfg = policy.shell_safety
    intent = isempty(cfg.intent) ? _SHELL_SAFETY_INTENT : cfg.intent
    do_not = isempty(cfg.do_not) ? _SHELL_SAFETY_DO_NOT : cfg.do_not
    diags = Violation[]
    seen = Set{Tuple{Int, Int}}()
    for fold in literals
        hazard = _cmd_argv_hazard(fold.value)
        hazard === nothing && continue
        key = (fold.byte_start, fold.byte_end)
        key in seen && continue
        push!(seen, key)
        _push_builtin_violation!(
            diags,
            "shell-safety/process-pattern",
            :preset,
            eff_level,
            fc.parsed.path,
            source,
            fold.byte_start,
            fold.byte_end,
            "hazardous shell pattern ($hazard)",
            intent,
            do_not,
        )
    end
    return diags
end
