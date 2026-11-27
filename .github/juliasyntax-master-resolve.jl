#!/usr/bin/env julia
# Daily CI: point [sources] JuliaSyntax at JuliaLang/julia master, then resolve.
# Never commit the rewritten Project.toml / Manifest.toml (ephemeral runner only).

using Pkg
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PKG = "JuliaSyntax"

function require_env(name::AbstractString)
    v = get(ENV, name, "")
    isempty(v) && error("$name must be set (from Daily pin-master / git fetch step)")
    return v
end

const MASTER_COMMIT = require_env("JULIASYNTAX_MASTER_COMMIT")
const EXPECTED_TREE = require_env("JULIASYNTAX_EXPECTED_TREE")

Pkg.activate(ROOT)
proj = TOML.parsefile(joinpath(ROOT, "Project.toml"))
sources = get(proj, "sources", Dict{String, Any}())
entry = get(sources, PKG, nothing)
entry isa Dict{String, Any} || error("Project.toml [sources] missing JuliaSyntax table")
haskey(entry, "url") || error("JuliaSyntax [sources] must have url (julia git subdir)")
entry["rev"] = MASTER_COMMIT
sources[PKG] = entry
proj["sources"] = sources
open(joinpath(ROOT, "Project.toml"), "w") do io
    TOML.print(io, proj)
end
Pkg.resolve()
Pkg.precompile()

function juliasyntax_manifest_entry()
    man = TOML.parsefile(joinpath(ROOT, "Manifest.toml"))
    pkgdeps = get(get(man, "deps", Dict{String, Any}()), PKG, nothing)
    pkgdeps === nothing && error("Manifest.toml missing deps.$PKG after resolve")
    if pkgdeps isa AbstractDict
        return pkgdeps
    elseif pkgdeps isa AbstractVector
        isempty(pkgdeps) && error("Manifest.toml deps.$PKG is empty after resolve")
        entry = pkgdeps[1]
        entry isa AbstractDict || error("Manifest deps.$PKG[1] must be a table")
        return entry
    end
    error("Manifest.toml deps.$PKG has unexpected type $(typeof(pkgdeps))")
end

entry = juliasyntax_manifest_entry()
manifest_tree = get(entry, "git-tree-sha1", nothing)
manifest_tree isa AbstractString && !isempty(manifest_tree) ||
    error("resolved JuliaSyntax manifest entry missing git-tree-sha1")
manifest_rev = get(entry, "repo-rev", nothing)

manifest_rev isa AbstractString && !isempty(manifest_rev) ||
    error("resolved JuliaSyntax manifest entry missing repo-rev")
println("juliasyntax-master-ci: commit=$(MASTER_COMMIT)")
println("juliasyntax-master-ci: expected JuliaSyntax tree=$(EXPECTED_TREE)")
println("juliasyntax-master-ci: manifest git-tree-sha1=$(manifest_tree)")
println("juliasyntax-master-ci: manifest repo-rev=$(manifest_rev)")
if manifest_rev != MASTER_COMMIT
    error(
        "JuliaSyntax manifest repo-rev $(manifest_rev) does not match commit $(MASTER_COMMIT)",
    )
end
if manifest_tree != EXPECTED_TREE
    error(
        "JuliaSyntax manifest git-tree-sha1 $(manifest_tree) does not match expected tree $(EXPECTED_TREE) for commit $(MASTER_COMMIT)",
    )
end
