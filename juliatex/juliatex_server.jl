# juliatex: servidor de Julia en segundo plano (lo lanza juliatex.lua si no está corriendo)
#   julia --project=<env> juliatex_server.jl <archivo-de-puerto>
# Escucha en 127.0.0.1. Cada petición es una línea con la carpeta .juliatex/<doc> (absoluta);
# responde "ok" al terminar. Guarda una sesión (módulo) por documento: si cambió el bloque k,
# los anteriores conservan su resultado y solo se ejecuta de k en adelante, con los paquetes
# ya cargados. Si cambia el primer bloque la sesión empieza de cero.
# Se apaga solo tras 30 minutos sin peticiones.

using Sockets
include(joinpath(@__DIR__, "juliatex.jl"))

mutable struct Sesion
    mod::Module
    huellas::Vector{String}
end

const sesiones = Dict{String,Sesion}()
const archivo_puerto = ARGS[1]
const inactividad = 30 * 60
ultimo_uso = time()

function atender(dir)
    tipos = readlines(joinpath(dir, "tipos"))
    huellas = readlines(joinpath(dir, "huellas"))
    s = get(sesiones, dir, nothing)
    # Primer bloque distinto (o sin resultado en disco) respecto a la última ejecución
    k = 1
    if s !== nothing
        while k <= min(length(huellas), length(s.huellas)) &&
              huellas[k] == s.huellas[k] && isfile(archivo(dir, k, "out"))
            k += 1
        end
    end
    if s === nothing || k == 1
        s = Sesion(Module(:JuliaTeX), String[])
        sesiones[dir] = s
    end
    # El código corre en la carpeta del .tex (savefig("x.pdf") queda junto al documento)
    cd(dirname(dirname(dir))) do
        ejecutar_bloques(dir, tipos, s.mod, k)
    end
    s.huellas = huellas
    return k
end

function main()
    # Fuera de cualquier carpeta de documentos (Windows no deja borrar la carpeta actual
    # de un proceso); cada petición entra y sale de la suya con cd(...) do
    cd(tempdir())
    puerto, servidor = listenany(ip"127.0.0.1", 8760)
    tmp = archivo_puerto * ".tmp"
    write(tmp, string(puerto, "\n", getpid(), "\n"))
    mv(tmp, archivo_puerto; force = true)
    atexit(() -> rm(archivo_puerto; force = true))
    Timer(60; interval = 60) do _
        if time() - ultimo_uso > inactividad
            close(servidor)
        end
    end
    while isopen(servidor)
        sock = try
            accept(servidor)
        catch
            break
        end
        try
            dir = readline(sock)
            k = atender(dir)
            println(sock, "ok ", k)
        catch err
            println(stderr, sprint(showerror, err, catch_backtrace()))
            try println(sock, "error") catch end
        finally
            close(sock)
            global ultimo_uso = time()
        end
    end
end

main()
