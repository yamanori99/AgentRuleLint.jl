# `catch e; …` header (semicolon separators are direct `;` children in the catch body block).
# Part A skips `K";"` in `_block_statements`; the old `SemicolonWs` summary never matched at this pin.
function swallow_catch_semicolon_header()
    try
        risky()
    catch e; return nothing
    end
end