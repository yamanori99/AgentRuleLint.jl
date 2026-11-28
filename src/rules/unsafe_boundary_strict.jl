const _UNSAFE_BOUNDARY_STRICT_EXPLAIN_ANCHOR = """
`@inbounds`, `@generated`, or `@assume_effects` (including qualified `Base.@assume_effects`).
Wrong `@inbounds` is undefined behavior; on many hot paths bounds checks are nearly free.
"""

const _UNSAFE_BOUNDARY_STRICT_EXPLAIN_CONFIG = """
Opt-in via `presets = ["unsafe-boundary/strict"]` in `$CONFIG_FILENAME`.
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
    Origin.PRESET,
    Level.WARN,
    "Flag `@inbounds`, `@generated`, and `@assume_effects` unless opt-in preset is enabled.",
    "Rely on core `unsafe-boundary` alone when skipping strict macro checks.",
    Dict{Symbol, String}(),
    "unsafe_boundary_strict.jl",
    "test_unsafe_boundary.jl",
    ("test/corpus/unsafe_inbounds.jl",),
)
