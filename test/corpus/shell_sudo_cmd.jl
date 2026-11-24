function demo_sudo()
    run(Cmd(["sudo", "apt", "update"]))
    return nothing
end
