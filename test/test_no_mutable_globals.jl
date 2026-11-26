const _SRC_ROOT = joinpath(ROOT, "src")

const _FORBIDDEN_GLOBAL_NAMES = (
    "BUILTIN_RULES",
    "init_registry!",
    "ID_PLACEHOLDER",
    "STR_PLACEHOLDER",
    "reset_anonymizer!",
)

const _MODULE_LEVEL_ASSIGN_SKIP_PREFIXES = (
    "abstract type ",
    "baremodule ",
    "const ",
    "end",
    "export ",
    "function ",
    "global const ",
    "if ",
    "import ",
    "include ",
    "macro ",
    "module ",
    "mutable struct ",
    "primitive type ",
    "return ",
    "struct ",
    "using ",
    "while ",
    "for ",
    "elseif ",
    "else",
)

function _src_julia_files(dir::AbstractString)
    out = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(f, ".jl") || continue
            push!(out, joinpath(root, f))
        end
    end
    return sort(out)
end

function _is_module_level_line(line::AbstractString)
    isempty(strip(line)) && return false
    return !startswith(line, ' ') && !startswith(line, '\t')
end

function _module_level_binding_line(line::AbstractString)
    s = strip(line)
    isempty(s) && return false
    startswith(s, '#') && return false
    for prefix in _MODULE_LEVEL_ASSIGN_SKIP_PREFIXES
        startswith(s, prefix) && return false
    end
    return occursin(r"^[A-Za-z_@][A-Za-z0-9_.]*\s*=", s)
end

function _collect_module_level_bindings(text::AbstractString)
    found = String[]
    for line in split(text, '\n')
        _is_module_level_line(line) || continue
        _module_level_binding_line(line) || continue
        push!(found, strip(line))
    end
    return found
end

const _RUNTIME_MUTATION_ON_UPPER = Regex(
    "\\b(?:empty!|push!|pop!|delete!|setindex!|getindex!)\\s*\\(\\s*([A-Z][A-Z0-9_]*)",
)

@testset "no mutable linter globals (src/)" begin
    for path in _src_julia_files(_SRC_ROOT)
        text = read(path, String)
        rel = relpath(path, ROOT)
        for name in _FORBIDDEN_GLOBAL_NAMES
            @test !occursin(name, text)
        end
        bindings = _collect_module_level_bindings(text)
        @test isempty(bindings) || error(
            "$rel: non-const module-level binding(s):\n$(join(bindings, '\n'))",
        )
        mut_ids = String[]
        for m in eachmatch(_RUNTIME_MUTATION_ON_UPPER, text)
            push!(mut_ids, m.captures[1])
        end
        @test isempty(mut_ids) || error(
            "$rel: runtime mutation on module-level name(s): $(join(mut_ids, ", "))",
        )
    end
end
