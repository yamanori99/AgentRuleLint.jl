#!/usr/bin/env julia
# Daily CI: point [sources] JuliaSyntax at JuliaLang/julia master, then resolve.
# Never commit the rewritten Project.toml / Manifest.toml (ephemeral runner only).

using Pkg
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PKG = "JuliaSyntax"

Pkg.activate(ROOT)
proj = TOML.parsefile(joinpath(ROOT, "Project.toml"))
sources = get(proj, "sources", Dict{String, Any}())
entry = get(sources, PKG, nothing)
entry isa Dict{String, Any} || error("Project.toml [sources] missing JuliaSyntax table")
haskey(entry, "url") || error("JuliaSyntax [sources] must have url (julia git subdir)")
entry["rev"] = "master"
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
rev = get(entry, "repo-rev", nothing)
rev isa AbstractString && !isempty(rev) ||
    error("resolved JuliaSyntax manifest entry missing repo-rev")
tree = get(entry, "git-tree-sha1", nothing)
tree isa AbstractString && !isempty(tree) ||
    error("resolved JuliaSyntax manifest entry missing git-tree-sha1")
println("juliasyntax-master-ci: resolved repo-rev=$rev")
println("juliasyntax-master-ci: resolved git-tree-sha1=$tree")