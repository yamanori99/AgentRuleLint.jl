try
    nothing
    # agentrulelint-expect: silent-catch reason="forbidden placement"
catch e
    e
end
