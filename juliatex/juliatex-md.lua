-- juliatex-md: filtro de pandoc que convierte un .tex con juliatex a Markdown (GitHub)
--   pandoc -f latex+raw_tex -t gfm --lua-filter=juliatex-md.lua -M juliatex-dir=.juliatex/doc
-- Lo llama juliatex.lua con la opción [md]. Usa los resultados que Julia ya dejó en
-- .juliatex/<documento>/NNN.out: no vuelve a ejecutar nada.
--   juliacode       -> bloque ```julia + su salida
--   juliarun        -> nada (como en el PDF), salvo que haya dado error
--   \juliav{expr}   -> el valor
--   \juliagraphics  -> imagen; si junto al .pdf hay un .svg o .png del mismo nombre, se usa
--                      ese (GitHub no muestra PDF dentro de un .md)

local dir
local n = 0 -- mismo orden que juliatex.lua: juliacode, juliarun y \juliav, en el documento
local figuras = {} -- [label] = número

local function leer(ruta)
  local f = io.open(ruta, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function resultado()
  n = n + 1
  local base = string.format("%s/%03d.", dir, n)
  local salida = leer(base .. "out")
  return salida and salida:gsub("%s+$", ""), (leer(base .. "status") or "ok")
end

local function imagen(archivo)
  local raiz = archivo:gsub("%.pdf$", "")
  for _, ext in ipairs({ ".svg", ".png" }) do
    if leer(raiz .. ext) then return raiz .. ext end
  end
  return archivo
end

local function bloque(raw)
  local tipo, codigo = raw.text:match("^\\begin{(julia%a+)}\n?(.-)\n?\\end{julia%a+}$")
  if tipo == "juliacode" or tipo == "juliarun" then
    local salida, estado = resultado()
    local r = {}
    if tipo == "juliacode" then r[1] = pandoc.CodeBlock(codigo, { class = "julia" }) end
    if salida and salida ~= "" and (tipo == "juliacode" or estado == "error") then
      -- crudo: con CodeBlock(salida, { class = "text" }) pandoc tarda ~1 s en buscar "text"
      r[#r + 1] = pandoc.RawBlock("gfm", "```text\n" .. salida .. "\n```")
    end
    return r
  end
  local opciones, archivo = raw.text:match("^\\juliagraphics%s*(%b[]){(.-)}$")
  if archivo or raw.text:match("^\\juliagraphics%s*{") then
    archivo = archivo or raw.text:match("{(.-)}")
    return pandoc.Plain({ pandoc.Image({}, imagen(archivo)) })
  end
  return {} -- \maketitle, \centering, ...
end

local function enlinea(raw)
  local expr = raw.text:match("^\\juliav%s*(%b{})$")
  if expr then
    local salida, estado = resultado()
    if estado == "error" then return pandoc.Code("error") end
    return pandoc.Str(salida or "??")
  end
  local ref = raw.text:match("^\\ref%s*{(.-)}$")
  if ref then return pandoc.Str(figuras[ref] or "??") end
  return {}
end

function Pandoc(doc)
  dir = pandoc.utils.stringify(doc.meta["juliatex-dir"] or ".juliatex")

  local k = 0
  doc:walk({ Figure = function(f)
    k = k + 1
    if f.identifier ~= "" then figuras[f.identifier] = tostring(k) end
  end })

  k = 0
  doc = doc:walk({
    traverse = "topdown",
    RawBlock = function(raw) if raw.format == "latex" then return bloque(raw) end end,
    RawInline = function(raw) if raw.format == "latex" then return enlinea(raw) end end,
    -- Figura: imagen y debajo "Figura n: título" (se ve igual en cualquier visor)
    Figure = function(f)
      k = k + 1
      local cuerpo = pandoc.Blocks(f.content):walk({
        RawBlock = function(raw) if raw.format == "latex" then return bloque(raw) end end,
      })
      local titulo = pandoc.utils.blocks_to_inlines(f.caption.long)
      cuerpo:insert(pandoc.Para({ pandoc.Emph({ pandoc.Str("Figura " .. k .. ":"),
        pandoc.Space(), table.unpack(titulo) }) }))
      return cuerpo, false
    end,
    -- \begin{equation}...\end{equation} -> $$...$$ (GitHub no acepta equation dentro)
    Math = function(m)
      if m.mathtype == "DisplayMath" then
        m.text = m.text:gsub("\\begin{equation%*?}", ""):gsub("\\end{equation%*?}", "")
          :gsub("\\label%b{}", ""):gsub("^%s+", ""):gsub("%s+$", "")
        return m
      end
    end,
  })

  -- Título y autor arriba, como \maketitle; las secciones bajan un nivel (# es el título)
  local cabecera = pandoc.Blocks({})
  if doc.meta.title then
    cabecera:insert(pandoc.Header(1, pandoc.utils.stringify(doc.meta.title)))
    doc.blocks = doc.blocks:walk({ Header = function(h) h.level = h.level + 1; return h end })
  end
  if doc.meta.author then
    cabecera:insert(pandoc.Para({ pandoc.Emph(pandoc.utils.stringify(doc.meta.author)) }))
  end
  cabecera:extend(doc.blocks)
  doc.blocks = cabecera
  doc.meta = {}
  return doc
end
