# juliatex: background Julia server (juliatex.lua starts it if it is not running)
#   julia --project=<env> juliatex_server.jl <port-file>
# Listens on 127.0.0.1. Each request is one line with the .juliatex/<doc> folder (absolute);
# it answers "ok" when done. It keeps one session (module) per document: if block k changed,
# the earlier ones keep their output and only blocks k onwards run, with the packages
# already loaded. If the first block changes, the session starts from scratch.
# It shuts down by itself after 30 minutes without requests.

using Sockets
include(joinpath(@__DIR__, "juliatex.jl"))

mutable struct Session
    mod::Module
    hashes::Vector{String}
end

const sessions = Dict{String,Session}()
const port_file = ARGS[1]
const idle_timeout = 30 * 60
last_used = time()

function handle(dir)
    kinds = readlines(joinpath(dir, "kinds"))
    hashes = readlines(joinpath(dir, "hashes"))
    s = get(sessions, dir, nothing)
    # First block that differs (or has no output on disk) from the last run
    k = 1
    if s !== nothing
        while k <= min(length(hashes), length(s.hashes)) &&
              hashes[k] == s.hashes[k] && isfile(blockfile(dir, k, "out"))
            k += 1
        end
    end
    if s === nothing || k == 1
        s = Session(Module(:JuliaTeX), String[])
        sessions[dir] = s
    end
    # The code runs in the .tex folder (savefig("x.pdf") ends up next to the document)
    cd(dirname(dirname(dir))) do
        run_blocks(dir, kinds, s.mod, k)
    end
    s.hashes = hashes
    return k
end

function main()
    # Outside any document folder (Windows does not let you delete a process's current
    # folder); each request enters and leaves its own with cd(...) do
    cd(tempdir())
    port, server = listenany(ip"127.0.0.1", 8760)
    tmp = port_file * ".tmp"
    write(tmp, string(port, "\n", getpid(), "\n"))
    mv(tmp, port_file; force = true)
    atexit(() -> rm(port_file; force = true))
    Timer(60; interval = 60) do _
        if time() - last_used > idle_timeout
            close(server)
        end
    end
    while isopen(server)
        sock = try
            accept(server)
        catch
            break
        end
        try
            dir = readline(sock)
            k = handle(dir)
            println(sock, "ok ", k)
        catch err
            println(stderr, sprint(showerror, err, catch_backtrace()))
            try println(sock, "error") catch end
        finally
            close(sock)
            global last_used = time()
        end
    end
end

main()
