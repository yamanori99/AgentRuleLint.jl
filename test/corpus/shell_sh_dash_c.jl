function demo_sh()
    run(Cmd(["sh", "-c", "rm -rf /tmp/x"]))
    return nothing
end
