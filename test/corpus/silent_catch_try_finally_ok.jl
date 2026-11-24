function cleanup_without_catch()
    return try
        work()
    finally
        done()
    end
end
