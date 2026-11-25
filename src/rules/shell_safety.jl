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

"""True when a short dashed shell option carries `-c` (e.g. `-c`, `-lc`, `-cl`, `-ec`).

Long options (`--…`) are excluded so names that merely contain `c` (e.g. `--rcfile`)
are not treated as `-c`.
"""
function _option_includes_dash_c(opt::AbstractString)
    startswith(opt, "-") || return false
    startswith(opt, "--") && return false
    opt == "-c" && return true
    return length(opt) > 2 && occursin('c', opt[2:end])
end

function _shell_dash_c_label(cmd::AbstractString)
    tokens = split(cmd; limit = 0)
    for i in 1:(length(tokens) - 1)
        shell = tokens[i]
        shell in ("sh", "bash") || continue
        for j in (i + 1):length(tokens)
            opt = tokens[j]
            opt == "--" && break
            if opt == "-c" || _option_includes_dash_c(opt)
                return "$(shell) -c"
            end
            # Keep scanning through leading options (`bash --norc -c …`); stop at the
            # first non-option operand (`bash --rcfile /tmp/x`).
            startswith(opt, "-") || break
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

const _SHELL_SAFETY_EXPLAIN_ANCHOR = """
`run(`, `open(`, `read(`, `pipeline(`, backtick Cmd, or `Cmd(`.
"""

const _SHELL_SAFETY_EXPLAIN_CONFIG = """
Opt-in via `presets = ["shell-safety"]` in `.AgentRuleLintConfig.toml`.
`[rules."shell-safety/process-pattern"]` without `presets = ["shell-safety"]` is ConfigError.
"""

const _SHELL_SAFETY_EXPLAIN_DETAIL = """
Uses the Syntax-layer constant folder and `collect_cmd_string_literals` to find `pkill`,
`killall`, `sh -c` / `bash -c`, `ssh --`, and `sudo` in folded command text. Short dashed
options containing `c` (`-c`, `-lc`, `-cl`, `-ec`) after `sh`/`bash` count as `-c` (combined
login/exec flags); long options (`--…`) do not. Qualified `Base.Cmd([...])` is analyzed like
`Cmd([...])`. Static folding limits: runtime Cmd values, string/cmd interpolation, and
symbols outside the shared fold budget are not analyzed (see `collect_cmd_string_literals`
docstring).
"""

function shell_safety_explain_extra()
    return Dict{Symbol, String}(
        :anchor_line => strip(_SHELL_SAFETY_EXPLAIN_ANCHOR),
        :config => strip(_SHELL_SAFETY_EXPLAIN_CONFIG),
        :detail => strip(_SHELL_SAFETY_EXPLAIN_DETAIL),
    )
end

const SHELL_SAFETY_RULE_DEF = RuleDef(
    SHELL_SAFETY_PRESET_ID,
    :preset,
    :deny,
    "Reject hazardous shell patterns in statically known Cmd literals.",
    "Split or dynamically assemble command strings to bypass constant folding.",
    Dict{Symbol, String}(),
    "shell_safety.jl",
    "test_shell_safety.jl",
    ("test/corpus/shell_sudo_cmd.jl",),
)

function diagnose_shell_safety(fc::FileContext, policy::PolicyBundle, eff_level::Symbol)
    source = fc.parsed.normalized
    tree = parse_source(source; filename = fc.parsed.path)
    collected = collect_cmd_string_literals(tree, source)
    cfg = policy.shell_safety
    intent = isempty(cfg.intent) ? _SHELL_SAFETY_INTENT : cfg.intent
    do_not = isempty(cfg.do_not) ? _SHELL_SAFETY_DO_NOT : cfg.do_not
    diags = Violation[]
    seen = Set{Tuple{Int, Int}}()
    for fold in collected.folds
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
    if collected.budget_exceeded
        at = max(1, collected.at_byte)
        push_analysis_incomplete!(
            diags,
            policy,
            fc.parsed.path,
            source,
            at,
            at,
            "shell-safety/process-pattern",
        )
    end
    return diags
end
