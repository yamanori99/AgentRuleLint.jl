try
    nothing
    # jailint-expect: silent-catch reason="forbidden placement"
catch e
    e
end
