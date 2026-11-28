# Catch body uses `;` separators (`K";"` children). Part A skips them in `_block_statements`;
# the old `SemicolonWs` summary never matched at the pinned JuliaSyntax revision.
function swallow_catch_semicolon_header()
    # agentrulelint-expect: silent-catch reason="semicolon-separated catch body (Part A gap corpus)"
    try
        risky()
    catch e
        x = 1; return nothing
    end
end
