function demo_folded_dash_c()
    run(Cmd(["sh", "-" * "c", "echo hi"]))
    return nothing
end
