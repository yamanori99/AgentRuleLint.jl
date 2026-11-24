const _SHELL_SAFETY_INTENT =
    "Reject hazardous process patterns in statically known shell/Cmd literals (pkill, killall, remote shells, sudo)."
const _SHELL_SAFETY_DO_NOT =
    "Split command names (\"pk\" * \"ill\"), alias binaries, or build Cmd from runtime values to evade folding."

const _SHELL_HAZARD_PATTERNS = [
    (r"\bpkill\b", "pkill"),
    (r"\bkillall\b", "killall"),
    (r"\bsh\b\s+-c\b", "sh -c"),
    (r"\bbash\b\s+-c\b", "bash -c"),
    (r"\bssh\b.*\s--\s", "ssh --"),
    (r"\bsudo\b", "sudo"),
]

function _cmd_argv_hazard(cmd::AbstractString)
    for (rx, label) in _SHELL_HAZARD_PATTERNS
        occursin(rx, cmd) && return label
    end
    tokens = split(cmd; limit = 0)
    for i in 1:(length(tokens) - 1)
        (tokens[i] == "sh" || tokens[i] == "bash") && tokens[i + 1] == "-c" && return "$(tokens[i]) -c"
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
