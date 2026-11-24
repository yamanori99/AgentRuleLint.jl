try
    nothing
    # agentrulelint-expect: project/no-internal-codename reason="must not suppress"
catch
    s = "INTERNAL_CODENAME"
end
