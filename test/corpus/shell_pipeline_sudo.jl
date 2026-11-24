function demo_pipeline()
    run(pipeline(`ls`, `sudo tee f`))
    return nothing
end
