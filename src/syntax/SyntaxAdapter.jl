# Syntax layer (included inside AgentRuleLint after types.jl)

include("normalize.jl")
include("parser.jl")
include("comments.jl")
include("expect_placement.jl")
include("constant_folder.jl")
include("try_catch_analysis.jl")
