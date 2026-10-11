# juliatex: runs the blocks that juliatex.lua left in <dir>/NNN.jl, in order and in
# a single session. For each block it writes:
#   NNN.out     what it printed + the final value (juliacode) or just the value (\juliav)
#   NNN.status  "ok" or "error"
# An error in a block is shown in the document and the following blocks keep running.
#
# As a script (julia juliatex.jl <dir>) it runs everything in Main: the fallback mode.
# juliatex_server.jl includes this file and uses run_blocks with a live session.

ENV["GKSwstype"] = "100"  # GR (Plots) without opening windows

blockfile(dir, n, ext) = joinpath(dir, string(lpad(n, 3, '0'), '.', ext))

# Final value as in the REPL: not shown if it is nothing or if the block ends with ;
function show_value(io, value, code)
    (value === nothing || endswith(rstrip(code), ';')) && return
    show(IOContext(io, :limit => true, :displaysize => (30, 90)), MIME"text/plain"(), value)
    println(io)
end

# Runs blocks from..end of dir in module mod
function run_blocks(dir, kinds, mod::Module, from::Int = 1)
    open(joinpath(dir, "julia.log"), "w") do log
        for n in from:length(kinds)
            kind = kinds[n]
            code = read(blockfile(dir, n, "jl"), String)
            state = "ok"
            open(blockfile(dir, n, "out"), "w") do io
                try
                    if kind == "value"
                        print(io, Base.invokelatest(Core.eval, mod, Meta.parse(code)))
                    else
                        value = redirect_stdout(io) do
                            redirect_stderr(io) do
                                include_string(mod, code, "block $n")
                            end
                        end
                        kind == "juliacode" && Base.invokelatest(show_value, io, value, code)
                    end
                catch err
                    state = "error"
                    bt = catch_backtrace()
                    msg = sprint(showerror, err isa LoadError ? err.error : err)
                    println(io, "ERROR: ", msg)
                    println(log, "block $n: ", sprint(showerror, err, bt))
                end
            end
            write(blockfile(dir, n, "status"), state)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = ARGS[1]
    run_blocks(dir, readlines(joinpath(dir, "kinds")), Main)
end
