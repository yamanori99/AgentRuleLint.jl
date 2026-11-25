function demo_cmd_pkill()
    run(Cmd(["pkill", "-f", "x"]))
    return nothing
end
