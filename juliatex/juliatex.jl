# juliatex: ejecuta los bloques que juliatex.lua dejó en <dir>/NNN.jl, en orden y en
# una misma sesión. Por cada bloque escribe:
#   NNN.out     lo que imprimió + el valor final (juliacode) o solo el valor (\juliav)
#   NNN.status  "ok" o "error"
# Un error en un bloque se muestra en el documento y los siguientes siguen corriendo.
#
# Como script (julia juliatex.jl <dir>) ejecuta todo en Main: es el modo de respaldo.
# juliatex_server.jl incluye este archivo y usa ejecutar_bloques con una sesión viva.

ENV["GKSwstype"] = "100"  # GR (Plots) sin abrir ventanas

archivo(dir, n, ext) = joinpath(dir, string(lpad(n, 3, '0'), '.', ext))

# Valor final como en el REPL: no se muestra si es nothing o si el bloque termina en ;
function mostrar_valor(io, valor, codigo)
    (valor === nothing || endswith(rstrip(codigo), ';')) && return
    show(IOContext(io, :limit => true, :displaysize => (30, 90)), MIME"text/plain"(), valor)
    println(io)
end

# Ejecuta los bloques desde..fin de dir en el módulo mod
function ejecutar_bloques(dir, tipos, mod::Module, desde::Int = 1)
    open(joinpath(dir, "julia.log"), "w") do log
        for n in desde:length(tipos)
            tipo = tipos[n]
            codigo = read(archivo(dir, n, "jl"), String)
            estado = "ok"
            open(archivo(dir, n, "out"), "w") do io
                try
                    if tipo == "valor"
                        print(io, Base.invokelatest(Core.eval, mod, Meta.parse(codigo)))
                    else
                        valor = redirect_stdout(io) do
                            redirect_stderr(io) do
                                include_string(mod, codigo, "bloque $n")
                            end
                        end
                        tipo == "juliacode" && Base.invokelatest(mostrar_valor, io, valor, codigo)
                    end
                catch err
                    estado = "error"
                    bt = catch_backtrace()
                    msg = sprint(showerror, err isa LoadError ? err.error : err)
                    println(io, "ERROR: ", msg)
                    println(log, "bloque $n: ", sprint(showerror, err, bt))
                end
            end
            write(archivo(dir, n, "status"), estado)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = ARGS[1]
    ejecutar_bloques(dir, readlines(joinpath(dir, "tipos")), Main)
end
