try
    nothing
    # jailint-expect: project/no-internal-codename reason="must not suppress"
catch
    x = "INTERNAL_CODENAME"
end
