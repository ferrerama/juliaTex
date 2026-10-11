-- juliatex: parte Lua de juliatex.sty
-- Captura el código de cada bloque, lo ejecuta en Julia al final del documento
-- (una sola sesión, todos los bloques en orden) y en la siguiente pasada inserta
-- los resultados. Si el código no cambió, no vuelve a llamar a Julia.

juliatex = {}
local J = juliatex

local aqui = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
-- Ruta absoluta: el servidor de Julia arranca en TEMP, no en la carpeta del documento
if not (aqui:match("^%a:") or aqui:match("^[/\\]")) then
  aqui = lfs.currentdir():gsub("\\", "/") .. "/" .. aqui:gsub("^%./", "")
end
local runner = aqui .. "/juliatex.jl"
-- Entorno de Julia: $JULIATEX_PROJECT o el Project.toml más cercano hacia arriba desde la
-- carpeta del documento (como julia --project=@.); nunca el entorno global
local function buscar_proyecto(d)
  while d do
    if lfs.isfile(d .. "/Project.toml") then return d end
    local padre = d:match("^(.*)[/\\][^/\\]+$")
    if not padre or padre == d then return nil end
    d = padre
  end
end
local proyecto = os.getenv("JULIATEX_PROJECT")
  or buscar_proyecto((lfs.currentdir():gsub("\\", "/")))
if not proyecto then
  tex.error("juliatex: no hay Project.toml en la carpeta del documento ni más arriba",
    { "Crea uno (julia --project=. -e 'using Pkg; Pkg.add(\"Plots\")')",
      "o define la variable JULIATEX_PROJECT con la carpeta del entorno." })
  proyecto = "."
end

local base = ".juliatex"
local dir = base .. "/" .. tex.jobname

local bloques = {}   -- { tipo = "juliacode"|"juliarun"|"valor", codigo = "..." }
local capturado

local function leer(ruta)
  local f = io.open(ruta, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function escribir(ruta, s)
  local f = assert(io.open(ruta, "wb"))
  f:write(s)
  f:close()
end

local function ruta(n, ext) return string.format("%s/%03d.%s", dir, n, ext) end

lfs.mkdir(base)
lfs.mkdir(dir)

local function aviso(msg)
  texio.write_nl("term and log", "Package juliatex Warning: " .. msg)
  texio.write_nl("term and log", "")
end

if status.shell_escape ~= 1 then
  tex.error("juliatex: hay que compilar con -shell-escape para poder lanzar Julia",
    { "Agrega un .latexmkrc junto al .tex con:",
      "  $pdf_mode = 4;",
      "  $lualatex = 'lualatex -shell-escape %O %S';" })
end

-- Las líneas entre \begin{...} y \end{...} no las ve TeX: las guarda Lua tal cual
function J.capturar(tipo)
  local lineas = {}
  local fin = "^%s*\\end%s*{" .. tipo .. "}"
  luatexbase.add_to_callback("process_input_buffer", function(linea)
    if linea:match(fin) then
      luatexbase.remove_from_callback("process_input_buffer", "juliatex")
      capturado = table.concat(lineas, "\n")
      return linea
    end
    table.insert(lineas, linea)
    return "%" -- línea vacía para TeX (sin \par)
  end, "juliatex")
end

-- Los resultados que lee Lua (no TeX) se anotan en el .fls: así latexmk ve que Julia los
-- cambió (o que apareció) y hace otra pasada; si no, un \juliav nuevo quedaba viejo en el PDF
local function anotar(archivo)
  if kpse.record_input_file then kpse.record_input_file(archivo) end
end

local function resultado(n)
  anotar(ruta(n, "out"))
  local salida = leer(ruta(n, "out"))
  if salida == nil then return nil end
  local estado = leer(ruta(n, "status")) or "ok"
  return salida, estado
end

function J.cerrar(tipo)
  local n = #bloques + 1
  bloques[n] = { tipo = tipo, codigo = capturado or "" }
  capturado = nil
  if select(2, resultado(n)) == "error" then
    aviso("Error de Julia en el bloque que termina en la línea " .. tex.inputlineno)
  end
  if tipo ~= "juliacode" then
    local _, estado = resultado(n)
    if estado == "error" then
      tex.sprint("\\JuliatexSalida{" .. ruta(n, "out") .. "}{error}")
    end
    return
  end
  escribir(ruta(n, "jl"), bloques[n].codigo .. "\n")
  tex.sprint("\\JuliatexCodigo{" .. ruta(n, "jl") .. "}")
  local salida, estado = resultado(n)
  if salida == nil then
    tex.sprint("\\par\\JuliatexPendiente\\par")
  elseif salida:match("%S") then
    tex.sprint("\\JuliatexSalida{" .. ruta(n, "out") .. "}{"
      .. (estado == "error" and "error" or "salida") .. "}")
  end
end

function J.valor(expr)
  local n = #bloques + 1
  bloques[n] = { tipo = "valor", codigo = expr }
  local salida, estado = resultado(n)
  if salida == nil then
    tex.sprint("\\JuliatexPendiente")
  elseif estado == "error" then
    tex.sprint("\\textcolor{juliatex@error}{\\texttt{error}}")
  else
    tex.sprint(-2, (salida:gsub("%s+$", "")))
  end
end

-- \juliagraphics: incluye una copia de la imagen (Julia puede reescribir el original con
-- savefig al final de esta pasada, cuando LuaTeX aún no termina de escribir el PDF)
local figuras = {} -- { original, copia }
function J.figura(archivo, opciones)
  anotar(archivo)
  local contenido = leer(archivo)
  if not contenido then
    tex.sprint("\\JuliatexSinFigura{")
    tex.sprint(-2, archivo)
    tex.sprint("}")
    figuras[#figuras + 1] = { archivo, nil }
    return
  end
  local copia = dir .. "/fig-" .. archivo:gsub("[/\\:]", "_")
  if leer(copia) ~= contenido then escribir(copia, contenido) end
  figuras[#figuras + 1] = { archivo, copia }
  tex.sprint("\\includegraphics[" .. opciones .. "]{" .. copia .. "}")
end

-- Servidor de Julia en segundo plano (juliatex_server.jl), uno por entorno. Su puerto
-- queda en %TEMP%/juliatex-<entorno>.port. Devuelve el bloque desde el que ejecutó, o nil
-- si no se pudo usar (entonces se usa el ejecutor de un solo uso).
local temp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
local archivo_puerto = temp .. "/juliatex-" .. md5.sumhexa(proyecto):sub(1, 8) .. ".port"

local function conectar(socket)
  local s = leer(archivo_puerto)
  local puerto = s and tonumber(s:match("^(%d+)"))
  if not puerto then return nil end
  local c = socket.tcp()
  c:settimeout(2)
  if c:connect("127.0.0.1", puerto) then return c end
  c:close()
end

local function lanzar_servidor()
  os.remove(archivo_puerto)
  local script = (aqui .. "/juliatex_server.jl"):gsub("\\", "/")
  if os.type == "windows" then
    -- Start-Process sin redirecciones: el servidor no hereda la salida de lualatex
    -- (si la heredara, latexmk/VimTeX esperarían a que el servidor terminara).
    -- Arranca en TEMP: en la carpeta del documento, Windows no dejaría borrarla ni renombrarla
    os.execute(string.format(
      'powershell -NoProfile -NonInteractive -Command "Start-Process -WindowStyle Hidden'
        .. " -WorkingDirectory '%s' -FilePath julia"
        .. " -ArgumentList '--startup-file=no','--project=%s','%s','%s'\"",
      temp, proyecto, script, archivo_puerto))
  else
    os.execute(string.format('julia --startup-file=no --project="%s" "%s" "%s" >/dev/null 2>&1 &',
      proyecto, script, archivo_puerto))
  end
end

function J.servidor(carpeta)
  local ok, socket = pcall(require, "socket")
  if not ok then return nil end
  local c = conectar(socket)
  if not c then
    texio.write_nl("term and log", "juliatex: iniciando el servidor de Julia...")
    lanzar_servidor()
    for _ = 1, 200 do -- hasta 20 s
      socket.sleep(0.1)
      c = conectar(socket)
      if c then break end
    end
    if not c then return nil end
  end
  c:settimeout(nil) -- la ejecución puede tardar lo que tarde el código
  c:send(carpeta .. "\n")
  local resp = c:receive("*l")
  c:close()
  return resp and tonumber(resp:match("^ok (%d+)"))
end

-- Opción [md]: <documento>.md junto al PDF (pandoc + juliatex-md.lua), con los mismos
-- resultados de Julia. Solo cuando ya no falta otra pasada, y solo si algo cambió
-- (el .tex, un resultado o una figura); pandoc tarda unas décimas de segundo.
J.md = false
local function markdown()
  if not J.md then return end
  local partes = { leer(tex.jobname .. ".tex") or "" }
  for n = 1, #bloques do partes[#partes + 1] = leer(ruta(n, "out")) or "" end
  for _, f in ipairs(figuras) do partes[#partes + 1] = leer(f[1]) or "" end
  local huella = md5.sumhexa(table.concat(partes, "\1"))
  local salida = tex.jobname .. ".md"
  if leer(dir .. "/huella-md") == huella and lfs.isfile(salida) then return end
  local pandoc = os.getenv("JULIATEX_PANDOC") or "pandoc"
  local cmd = string.format('%s -f latex+raw_tex -t gfm --wrap=none --lua-filter="%s"'
      .. ' -M juliatex-dir="%s" -o "%s" "%s"',
    pandoc, aqui .. "/juliatex-md.lua", dir, salida, tex.jobname .. ".tex")
  if os.execute(cmd) then
    escribir(dir .. "/huella-md", huella)
    texio.write_nl("term and log", "juliatex: " .. salida .. " actualizado")
  else
    aviso("no se pudo generar " .. salida .. " (¿pandoc instalado y en el PATH?)")
  end
end

-- Al final del documento: si el código cambió, correr Julia y pedir otra pasada
function J.ejecutar()
  if #bloques == 0 then return markdown() end
  local partes = { proyecto }
  for n, b in ipairs(bloques) do
    partes[#partes + 1] = n .. "\0" .. b.tipo .. "\0" .. b.codigo
  end
  local huella = md5.sumhexa(table.concat(partes, "\1"))
  if leer(dir .. "/huella") == huella then return markdown() end

  local tipos = {}
  for n, b in ipairs(bloques) do
    escribir(ruta(n, "jl"), b.codigo .. "\n")
    tipos[n] = b.tipo
  end
  escribir(dir .. "/tipos", table.concat(tipos, "\n") .. "\n")

  local huellas = {}
  for n, b in ipairs(bloques) do huellas[n] = md5.sumhexa(b.tipo .. "\0" .. b.codigo) end
  escribir(dir .. "/huellas", table.concat(huellas, "\n") .. "\n")

  local antes = {}
  for n = 1, #bloques do antes[n] = leer(ruta(n, "out")) end

  -- Primero el servidor (sesión viva: paquetes cargados, solo desde el bloque que cambió);
  -- si no está disponible, un Julia nuevo con todo en orden, como siempre
  local desde = J.servidor(lfs.currentdir():gsub("\\", "/") .. "/" .. dir)
  if desde then
    texio.write_nl("term and log", "juliatex: servidor ejecutó desde el bloque " .. desde
      .. " de " .. #bloques)
  else
    texio.write_nl("term and log", "juliatex: ejecutando " .. #bloques .. " bloques en Julia...")
    local cmd = string.format('julia --startup-file=no --project="%s" "%s" "%s"',
      proyecto, runner, dir)
    local ok = os.execute(cmd)
    if not ok then
      aviso("Julia terminó con error; revisa " .. dir .. "/julia.log")
      return
    end
  end
  escribir(dir .. "/huella", huella)

  for n = 1, #bloques do
    if leer(ruta(n, "out")) ~= antes[n] then
      aviso("Rerun to get Julia outputs right.")
      return
    end
  end
  -- Gráficas nuevas o distintas de la copia incluida en esta pasada
  for _, f in ipairs(figuras) do
    local actual = leer(f[1])
    if actual and (not f[2] or leer(f[2]) ~= actual) then
      aviso("Rerun to get Julia outputs right.")
      return
    end
  end
  markdown()
end

return J
