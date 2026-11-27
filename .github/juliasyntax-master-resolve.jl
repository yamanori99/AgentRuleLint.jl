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
