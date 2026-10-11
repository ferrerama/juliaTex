-- juliatex-md: pandoc filter that turns a .tex with juliatex into Markdown (GitHub)
--   pandoc -f latex+raw_tex -t gfm --lua-filter=juliatex-md.lua -M juliatex-dir=.juliatex/doc
-- juliatex.lua calls it with the [md] option. It uses the outputs Julia already left in
-- .juliatex/<document>/NNN.out: it does not run anything again.
--   juliacode       -> ```julia block + its output
--   juliarun        -> nothing (as in the PDF), unless it failed
--   \juliav{expr}   -> the value
--   \juliagraphics  -> image; if there is a .svg or .png with the same name next to the .pdf,
--                      that one is used (GitHub does not show PDF inside a .md)

local dir
local n = 0 -- same order as juliatex.lua: juliacode, juliarun and \juliav, in the document
local figures = {} -- [label] = number

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function result()
  n = n + 1
  local base = string.format("%s/%03d.", dir, n)
  local output = read(base .. "out")
  return output and output:gsub("%s+$", ""), (read(base .. "status") or "ok")
end

local function image(file)
  local root = file:gsub("%.pdf$", "")
  for _, ext in ipairs({ ".svg", ".png" }) do
    if read(root .. ext) then return root .. ext end
  end
  return file
end

local function block(raw)
  local kind, code = raw.text:match("^\\begin{(julia%a+)}\n?(.-)\n?\\end{julia%a+}$")
  if kind == "juliacode" or kind == "juliarun" then
    local output, state = result()
    local r = {}
    if kind == "juliacode" then r[1] = pandoc.CodeBlock(code, { class = "julia" }) end
    if output and output ~= "" and (kind == "juliacode" or state == "error") then
      -- raw: with CodeBlock(output, { class = "text" }) pandoc spends ~1 s looking up "text"
      r[#r + 1] = pandoc.RawBlock("gfm", "```text\n" .. output .. "\n```")
    end
    return r
  end
  local options, file = raw.text:match("^\\juliagraphics%s*(%b[]){(.-)}$")
  if file or raw.text:match("^\\juliagraphics%s*{") then
    file = file or raw.text:match("{(.-)}")
    return pandoc.Plain({ pandoc.Image({}, image(file)) })
  end
  return {} -- \maketitle, \centering, ...
end

local function inline(raw)
  local expr = raw.text:match("^\\juliav%s*(%b{})$")
  if expr then
    local output, state = result()
    if state == "error" then return pandoc.Code("error") end
    return pandoc.Str(output or "??")
  end
  local ref = raw.text:match("^\\ref%s*{(.-)}$")
  if ref then return pandoc.Str(figures[ref] or "??") end
  return {}
end

function Pandoc(doc)
  dir = pandoc.utils.stringify(doc.meta["juliatex-dir"] or ".juliatex")

  local k = 0
  doc:walk({ Figure = function(f)
    k = k + 1
    if f.identifier ~= "" then figures[f.identifier] = tostring(k) end
  end })

  k = 0
  doc = doc:walk({
    traverse = "topdown",
    RawBlock = function(raw) if raw.format == "latex" then return block(raw) end end,
    RawInline = function(raw) if raw.format == "latex" then return inline(raw) end end,
    -- Figure: image and "Figure n: caption" below it (looks the same in any viewer)
    Figure = function(f)
      k = k + 1
      local body = pandoc.Blocks(f.content):walk({
        RawBlock = function(raw) if raw.format == "latex" then return block(raw) end end,
      })
      local caption = pandoc.utils.blocks_to_inlines(f.caption.long)
      body:insert(pandoc.Para({ pandoc.Emph({ pandoc.Str("Figure " .. k .. ":"),
        pandoc.Space(), table.unpack(caption) }) }))
      return body, false
    end,
    -- \begin{equation}...\end{equation} -> $$...$$ (GitHub does not accept equation inside)
    Math = function(m)
      if m.mathtype == "DisplayMath" then
        m.text = m.text:gsub("\\begin{equation%*?}", ""):gsub("\\end{equation%*?}", "")
          :gsub("\\label%b{}", ""):gsub("^%s+", ""):gsub("%s+$", "")
        return m
      end
    end,
  })

  -- Title and author on top, like \maketitle; sections go down one level (# is the title)
  local header = pandoc.Blocks({})
  if doc.meta.title then
    header:insert(pandoc.Header(1, pandoc.utils.stringify(doc.meta.title)))
    doc.blocks = doc.blocks:walk({ Header = function(h) h.level = h.level + 1; return h end })
  end
  if doc.meta.author then
    header:insert(pandoc.Para({ pandoc.Emph(pandoc.utils.stringify(doc.meta.author)) }))
  end
  header:extend(doc.blocks)
  doc.blocks = header
  doc.meta = {}
  return doc
end
