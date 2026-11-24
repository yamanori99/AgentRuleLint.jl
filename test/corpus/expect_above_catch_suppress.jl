try
    nothing
    # jailint-expect: project/no-internal-codename reason="must not suppress"
catch
    s = "INTERNAL_CODENAME"
end
