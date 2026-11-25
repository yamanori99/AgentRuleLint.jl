# Built-in `analysis-incomplete`: fail-closed when static analysis truncates
# (e.g. constant-fold step budget). Integrity forbid; never expect-suppressible.

const ANALYSIS_INCOMPLETE_MSG_PREFIX = "analysis incomplete: constant-fold budget exceeded"

function analysis_incomplete_message(path::AbstractString, analyzer::AbstractString)
    return "$ANALYSIS_INCOMPLETE_MSG_PREFIX in $path ($analyzer)"
end

function is_analysis_incomplete(d::Violation)
    return d.rule_id == ANALYSIS_INCOMPLETE_RULE
end

function _analysis_incomplete_docs(policy::PolicyBundle)
    spec = get(policy.rules, ANALYSIS_INCOMPLETE_RULE, nothing)
    if spec === nothing
        return ANALYSIS_INCOMPLETE_RULE_DEF.intent, ANALYSIS_INCOMPLETE_RULE_DEF.do_not
    end
    intent = isempty(spec.intent) ? ANALYSIS_INCOMPLETE_RULE_DEF.intent : spec.intent
    do_not = isempty(spec.do_not) ? ANALYSIS_INCOMPLETE_RULE_DEF.do_not : spec.do_not
    return intent, do_not
end

"""Push a `:forbid` `analysis-incomplete` finding (constant-fold budget exhaustion).

`analyzer` names the folding call site (e.g. `project/<id>`, `test-integrity`,
`shell-safety/process-pattern`). Skips if `diags` already has a finding for `path`.
"""
function push_analysis_incomplete!(
        diags::Vector{Violation},
        policy::PolicyBundle,
        path::String,
        source::AbstractString,
        byte_start::Int,
        byte_end::Int,
        analyzer::AbstractString,
    )
    any(d -> is_analysis_incomplete(d) && d.path == path, diags) && return nothing
    intent, do_not = _analysis_incomplete_docs(policy)
    sp = span_from_byte_range(source, byte_start, byte_end)
    push!(
        diags,
        Violation(
            ANALYSIS_INCOMPLETE_RULE,
            :agentrulelint,
            :forbid,
            path,
            sp,
            sp.start_line,
            "",
            :none,
            false,
            analysis_incomplete_message(path, analyzer),
            intent,
            do_not,
        ),
    )
    return nothing
end

"""Keep one `analysis-incomplete` finding per path; prefer the more specific span."""
function dedupe_analysis_incomplete!(diags::Vector{Violation})
    best = Dict{String, Int}()
    drop = Set{Int}()
    for (i, d) in enumerate(diags)
        is_analysis_incomplete(d) || continue
        if haskey(best, d.path)
            j = best[d.path]
            prev = diags[j]
            prefer_new =
                (d.span.start_line, d.span.start_col, d.span.end_line, d.span.end_col) >
                (prev.span.start_line, prev.span.start_col, prev.span.end_line, prev.span.end_col)
            if prefer_new
                push!(drop, j)
                best[d.path] = i
            else
                push!(drop, i)
            end
        else
            best[d.path] = i
        end
    end
    isempty(drop) && return diags
    return Violation[d for (i, d) in enumerate(diags) if !(i in drop)]
end

const _ANALYSIS_INCOMPLETE_EXPLAIN_DETAIL = """
Emitted when a constant-fold walk hits the shared step budget (`FOLD_MAX_STEPS`)
before finishing. Call sites include project-rule literal folding, shell-safety Cmd
folding, and test-integrity `@test` value folding. The finding is integrity
`forbid` and cannot be suppressed with `# agentrulelint-expect:`. At most one
finding is reported per file; the message names the analyzer. Fix by simplifying
the expression (shorter concatenations or `@test` chains) so static folding can finish.
"""

function analysis_incomplete_explain_extra()
    return Dict{Symbol, String}(:detail => strip(_ANALYSIS_INCOMPLETE_EXPLAIN_DETAIL))
end

const ANALYSIS_INCOMPLETE_RULE_DEF = RuleDef(
    ANALYSIS_INCOMPLETE_RULE,
    :agentrulelint,
    :forbid,
    "Fail closed when static analysis cannot finish (constant-fold budget).",
    "Pad files with enough folds to exhaust the budget and hide later findings, or suppress the incomplete diagnostic.",
    Dict{Symbol, String}(),
    "analysis_incomplete.jl",
    "test_analysis_incomplete.jl",
    ("test/corpus/test_integrity_fold_budget.jl",),
)
