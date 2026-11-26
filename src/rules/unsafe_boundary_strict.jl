const _UNSAFE_BOUNDARY_STRICT_INTENT =
    "Flag `@inbounds`, `@generated`, and `@assume_effects` unless opt-in preset is enabled."
const _UNSAFE_BOUNDARY_STRICT_DO_NOT =
    "Rely on core `unsafe-boundary` alone when skipping strict macro checks."

const _UNSAFE_BOUNDARY_STRICT_EXPLAIN_ANCHOR = """
`@inbounds`, `@generated`, or `@assume_effects` (including qualified `Base.@assume_effects`).
Wrong `@inbounds` is undefined behavior; on many hot paths bounds checks are nearly free.
"""

const _UNSAFE_BOUNDARY_STRICT_EXPLAIN_CONFIG = """
Opt-in via `presets = ["unsafe-boundary/strict"]` in `.AgentRuleLintConfig.toml`.
`[rules."unsafe-boundary/strict"]` without the preset is ConfigError.
Respects `[rules.unsafe-boundary]` `allow_modules` / `allow_globs` when that rule is configured.
"""

function unsafe_boundary_strict_explain_extra()
    return Dict{Symbol, String}(
        :anchor_line => strip(_UNSAFE_BOUNDARY_STRICT_EXPLAIN_ANCHOR),
        :config => strip(_UNSAFE_BOUNDARY_STRICT_EXPLAIN_CONFIG),
    )
end

const UNSAFE_BOUNDARY_STRICT_RULE_DEF = RuleDef(
    UNSAFE_BOUNDARY_STRICT_PRESET_ID,
    :preset,
    :warn,
    _UNSAFE_BOUNDARY_STRICT_INTENT,
    _UNSAFE_BOUNDARY_STRICT_DO_NOT,
    Dict{Symbol, String}(),
    "unsafe_boundary_strict.jl",
    "test_unsafe_boundary.jl",
    ("test/corpus/unsafe_inbounds.jl",),
)
