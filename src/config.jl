using TOML

const CONFIG_FILENAME = ".JAILintConfig.toml"
const CEILINGS_REL = ".jailint/ceilings.toml"

_rule_level(s::AbstractString) = Symbol(lowercase(s))
_rule_level(s::Symbol) = s

function _require_string(dict, key, path)
    haskey(dict, key) || throw(ConfigError("missing key '$key' in $path"))
    v = dict[key]
    v isa AbstractString || throw(ConfigError("expected string for '$key' in $path"))
    return String(v)
end

function _opt_string(dict, key, default = "")
    !haskey(dict, key) && return default
    v = dict[key]
    v isa AbstractString || throw(ConfigError("expected string for '$key'"))
    return String(v)
end

function _parse_version_pin(raw::AbstractString)
    s = strip(raw)
    startswith(s, "=") && return VersionNumber(s[2:end])
    return VersionNumber(s)
end

function validate_jailint_version!(toml_version::VersionNumber, pkg::VersionNumber)
    pkg_major, pkg_minor = pkg.major, pkg.minor
    return if toml_version.major != pkg_major || toml_version.minor != pkg_minor
        throw(
            ConfigError(
                "jailint_version pin $(toml_version) does not match JAILint $(pkg)",
            )
        )
    end
end

function load_toml_string(toml_string::String, path_label::String)
    try
        return TOML.parse(toml_string)
    catch err
        throw(ParseError("TOML parse error in $path_label: $(err)"))
    end
end

function load_toml_file(path::String)
    isfile(path) || throw(ConfigError("config not found: $path"))
    try
        return TOML.parsefile(path)
    catch err
        throw(ParseError("TOML parse error in $path: $(err)"))
    end
end

function _load_rules_table(raw::Dict)
    rules = Dict{String, LoadedRule}()
    for (section, content) in raw
        startswith(section, "rules.") || continue
        id = section[7:end]
        content isa Dict || throw(ConfigError("rules.$id must be a table"))
        level = _rule_level(get(content, "level", "deny"))
        intent = _opt_string(content, "intent")
        do_not = _opt_string(content, "do_not")
        extra_keys = filter(k -> k ∉ ("level", "intent", "do_not"), collect(keys(content)))
        pairs = Tuple(Symbol(k) => content[k] for k in extra_keys)
        extra = isempty(pairs) ? NamedTuple() : NamedTuple(pairs)
        code = "JA004"
        if id == "expect-audit"
            code = "JA004"
        end
        rules[id] = LoadedRule(code, id, :jailint, level, intent, do_not, extra)
    end
    return rules
end

function _load_project_rules(raw::Vector)
    out = ProjectRule[]
    for (i, entry) in enumerate(raw)
        entry isa Dict || throw(ConfigError("project_rules[$i] must be a table"))
        id = _require_string(entry, "id", "project_rules[$i]")
        level = _rule_level(get(entry, "level", "deny"))
        paths = get(entry, "paths", String[])
        paths = [String(p) for p in paths]
        literals = get(entry, "forbid_literals", String[])
        literals = [String(l) for l in literals]
        intent = _opt_string(entry, "intent")
        do_not = _opt_string(entry, "do_not")
        push!(out, ProjectRule(id, level, paths, literals, intent, do_not))
    end
    return out
end

function build_policy(raw::Dict, config_path::String, source::Dict)
    ver_raw = _require_string(raw, "jailint_version", CONFIG_FILENAME)
    ver = _parse_version_pin(ver_raw)
    validate_jailint_version!(ver, JAILINT_VERSION)
    fmt = Symbol(get(raw, "default_format", "human"))
    max_hits = Int(get(raw, "max_hits_per_rule", 20))
    presets = [String(p) for p in get(raw, "presets", String[])]
    rules = _load_rules_table(raw)
    project = _load_project_rules(get(raw, "project_rules", []))
    on_allow = :warn
    expect_section = nothing
    for (k, v) in raw
        k == "rules.expect-audit" && (expect_section = v)
    end
    if expect_section isa Dict && haskey(expect_section, "on_allow_rule")
        on_allow = Symbol(expect_section["on_allow_rule"])
    end
    return PolicyBundle(ver, fmt, max_hits, presets, rules, project, on_allow, config_path, source)
end

function policy_from_dict(raw::Dict, config_path::String; source = Dict{String, Any}())
    isempty(source) && (source = Dict{String, Any}("kind" => "path", "path" => config_path))
    return build_policy(raw, config_path, source)
end

function load_policy(root::AbstractString; config_path = nothing)
    root = abspath(String(root))
    cfg = something(config_path, joinpath(root, CONFIG_FILENAME))
    raw = load_toml_file(cfg)
    source = Dict{String, Any}("kind" => "path", "path" => relpath(cfg, root))
    return policy_from_dict(raw, cfg; source)
end

function load_ceilings(root::AbstractString)
    path = joinpath(abspath(root), CEILINGS_REL)
    !isfile(path) && return CeilingEntry(Dict(), Dict())
    raw = load_toml_file(path)
    viol = Dict{String, Dict{String, Int}}()
    for (k, v) in raw
        startswith(k, "violations.") || continue
        rid = k[12:end]
        viol[rid] = Dict{String, Int}(String(p) => Int(c) for (p, c) in v)
    end
    exp = Dict{String, Dict{String, Int}}()
    for (k, v) in raw
        startswith(k, "expects.") || continue
        rid = k[9:end]
        exp[rid] = Dict{String, Int}(String(p) => Int(c) for (p, c) in v)
    end
    return CeilingEntry(viol, exp)
end

function git_show_file(ref::AbstractString, relpath::AbstractString, root::AbstractString)
    root = abspath(String(root))
    reff = string(ref, "^{commit}")
    sha_cmd = Cmd(["git", "-C", root, "rev-parse", "--verify", "--end-of-options", reff])
    sha = strip(String(read(sha_cmd)))
    showspec = string(sha, ":", relpath)
    show_cmd = Cmd(["git", "-C", root, "show", showspec])
    return strip(String(read(show_cmd))), sha
end

function load_policy_from_ref(root::AbstractString, ref::AbstractString)
    root = abspath(String(root))
    try
        cfg_text, sha = git_show_file(ref, CONFIG_FILENAME, root)
        raw = load_toml_string(cfg_text, "$CONFIG_FILENAME@$ref")
        source = Dict{String, Any}(
            "kind" => "git-ref",
            "ref" => String(ref),
            "sha" => sha,
        )
        cfg_path = joinpath(root, CONFIG_FILENAME)
        return build_policy(raw, cfg_path, source)
    catch err
        err isa ConfigError || err isa ParseError && rethrow()
        err isa ErrorException || err isa GitError && rethrow()
        throw(GitError("failed loading policy from ref $(ref): $(err)"))
    end
end

function default_policy(root::AbstractString)
    ver = JAILINT_VERSION
    rules = Dict{String, LoadedRule}(
        "expect-audit" => LoadedRule(
            "JA004",
            "expect-audit",
            :jailint,
            :forbid,
            "Keep suppression comments auditable and fail-closed.",
            "Use inline or block comment expects to hide violations.",
            NamedTuple(),
        ),
    )
    source = Dict{String, Any}("kind" => "built-in-default")
    cfg = joinpath(abspath(root), CONFIG_FILENAME)
    return PolicyBundle(
        ver,
        :human,
        20,
        String[],
        rules,
        ProjectRule[],
        :warn,
        cfg,
        source,
    )
end

function resolve_policy(root::AbstractString; config_path = nothing, config_from = nothing)
    if config_from !== nothing
        return load_policy_from_ref(root, config_from)
    end
    cfg = something(config_path, joinpath(abspath(root), CONFIG_FILENAME))
    if isfile(cfg)
        return load_policy(root; config_path = cfg)
    end
    return default_policy(root)
end
