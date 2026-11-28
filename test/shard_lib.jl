# Shared i/N shard parse and round-robin selection (Pkg.test + mutation runner).

const AGENTRULELINT_MUTATION_SHARD_ENV = "AGENTRULELINT_MUTATION_SHARD"

function parse_mutation_shard()
    raw = get(ENV, AGENTRULELINT_MUTATION_SHARD_ENV, "")
    if isempty(strip(raw))
        return nothing
    end
    s = strip(raw)
    m = match(r"^(\d+)/(\d+)$", s)
    m === nothing && throw(
        ArgumentError(
            "AGENTRULELINT_MUTATION_SHARD must be \"i/N\" with positive integers, got $(repr(raw))",
        ),
    )
    i = parse(Int, m.captures[1]::SubString)
    n = parse(Int, m.captures[2]::SubString)
    n < 1 && throw(ArgumentError("AGENTRULELINT_MUTATION_SHARD denominator N must be >= 1, got $n"))
    i < 1 && throw(ArgumentError("AGENTRULELINT_MUTATION_SHARD shard index i must be >= 1, got $i"))
    i > n && throw(ArgumentError("AGENTRULELINT_MUTATION_SHARD shard index i must be <= N, got $i/$n"))
    return (i, n)
end

function select_mutation_shard(items::AbstractVector, i::Int, n::Int)
    return [s for (k, s) in enumerate(items) if (k - 1) % n == i - 1]
end

function apply_mutation_shard(items::Vector{String})
    shard = parse_mutation_shard()
    shard === nothing && return items
    i, n = shard
    return select_mutation_shard(items, i, n)
end
