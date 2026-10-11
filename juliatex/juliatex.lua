-- juliatex: Lua side of juliatex.sty
-- Captures the code of each block, runs it in Julia at the end of the document
-- (a single session, all blocks in order) and inserts the results on the next pass.
-- If the code did not change, Julia is not called again.

juliatex = {}
local J = juliatex

local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
-- Absolute path: the Julia server starts in TEMP, not in the document folder
if not (here:match("^%a:") or here:match("^[/\\]")) then
  here = lfs.currentdir():gsub("\\", "/") .. "/" .. here:gsub("^%./", "")
end
local runner = here .. "/juliatex.jl"
-- Julia environment: $JULIATEX_PROJECT or the nearest Project.toml going up from the
-- document folder (like julia --project=@.); never the global environment
local function find_project(d)
  while d do
    if lfs.isfile(d .. "/Project.toml") then return d end
    local parent = d:match("^(.*)[/\\][^/\\]+$")
    if not parent or parent == d then return nil end
    d = parent
  end
end
local project = os.getenv("JULIATEX_PROJECT")
  or find_project((lfs.currentdir():gsub("\\", "/")))
if not project then
  tex.error("juliatex: no Project.toml in the document folder or above it",
    { "Create one (julia --project=. -e 'using Pkg; Pkg.add(\"Plots\")')",
      "or set JULIATEX_PROJECT to the environment folder." })
  project = "."
end

local base = ".juliatex"
local dir = base .. "/" .. tex.jobname

local blocks = {}   -- { kind = "juliacode"|"juliarun"|"value", code = "..." }
local captured

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local function path(n, ext) return string.format("%s/%03d.%s", dir, n, ext) end

lfs.mkdir(base)
lfs.mkdir(dir)

-- In LuaTeX os.execute returns the exit code (a number, truthy even when it is 1)
local function run(cmd)
  local r = os.execute(cmd)
  return r == true or r == 0
end

local function warning(msg)
  texio.write_nl("term and log", "Package juliatex Warning: " .. msg)
  texio.write_nl("term and log", "")
end

if status.shell_escape ~= 1 then
  tex.error("juliatex: compile with -shell-escape so that Julia can be launched",
    { "Add a .latexmkrc next to the .tex with:",
      "  $pdf_mode = 4;",
      "  $lualatex = 'lualatex -shell-escape %O %S';" })
end

-- TeX never sees the lines between \begin{...} and \end{...}: Lua keeps them verbatim
function J.capture(kind)
  local lines = {}
  local stop = "^%s*\\end%s*{" .. kind .. "}"
  luatexbase.add_to_callback("process_input_buffer", function(line)
    if line:match(stop) then
      luatexbase.remove_from_callback("process_input_buffer", "juliatex")
      captured = table.concat(lines, "\n")
      return line
    end
    table.insert(lines, line)
    return "%" -- empty line for TeX (no \par)
  end, "juliatex")
end

-- Outputs read by Lua (not TeX) are recorded in the .fls: that way latexmk sees that Julia
-- changed them and runs another pass; otherwise a new \juliav value stayed stale in the PDF
local function record(file)
  if kpse.record_input_file then kpse.record_input_file(file) end
end

-- latexmk ignores the "Rerun" warning: it only reruns if a file in the .fls that existed
-- when the pass started has changed. A new figure did not exist, so this marker changes
local marker = dir .. "/pass"
if not read(marker) then write(marker, "0\n") end
record(marker)
local function another_pass()
  write(marker, os.time() .. " " .. os.clock() .. "\n")
  warning("Rerun to get Julia outputs right.")
end

local function result(n)
  record(path(n, "out"))
  local output = read(path(n, "out"))
  if output == nil then return nil end
  local state = read(path(n, "status")) or "ok"
  return output, state
end

function J.close(kind)
  local n = #blocks + 1
  blocks[n] = { kind = kind, code = captured or "" }
  captured = nil
  if select(2, result(n)) == "error" then
    warning("Julia error in the block ending on line " .. tex.inputlineno)
  end
  if kind ~= "juliacode" then
    local _, state = result(n)
    if state == "error" then
      tex.sprint("\\JuliatexOutput{" .. path(n, "out") .. "}{error}")
    end
    return
  end
  write(path(n, "jl"), blocks[n].code .. "\n")
  tex.sprint("\\JuliatexCode{" .. path(n, "jl") .. "}")
  local output, state = result(n)
  if output == nil then
    tex.sprint("\\par\\JuliatexPending\\par")
  elseif output:match("%S") then
    tex.sprint("\\JuliatexOutput{" .. path(n, "out") .. "}{"
      .. (state == "error" and "error" or "output") .. "}")
  end
end

function J.value(expr)
  local n = #blocks + 1
  blocks[n] = { kind = "value", code = expr }
  local output, state = result(n)
  if output == nil then
    tex.sprint("\\JuliatexPending")
  elseif state == "error" then
    tex.sprint("\\textcolor{juliatex@error}{\\texttt{error}}")
  else
    tex.sprint(-2, (output:gsub("%s+$", "")))
  end
end

-- \juliagraphics: includes a copy of the image (Julia may rewrite the original with
-- savefig at the end of this pass, while LuaTeX is still writing the PDF)
local figures = {} -- { original, copy }
function J.graphics(file, options)
  record(file)
  local content = read(file)
  if not content then
    tex.sprint("\\JuliatexNoFigure{")
    tex.sprint(-2, file)
    tex.sprint("}")
    figures[#figures + 1] = { file, nil }
    return
  end
  local copy = dir .. "/fig-" .. file:gsub("[/\\:]", "_")
  if read(copy) ~= content then write(copy, content) end
  figures[#figures + 1] = { file, copy }
  tex.sprint("\\includegraphics[" .. options .. "]{" .. copy .. "}")
end

-- Background Julia server (juliatex_server.jl), one per environment. Its port is kept in
-- %TEMP%/juliatex-<environment>.port. Returns the block it ran from, or nil if it could
-- not be used (then the one-shot runner is used).
local temp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
local port_file = temp .. "/juliatex-" .. md5.sumhexa(project):sub(1, 8) .. ".port"

local function connect(socket)
  local s = read(port_file)
  local port = s and tonumber(s:match("^(%d+)"))
  if not port then return nil end
  local c = socket.tcp()
  c:settimeout(2)
  if c:connect("127.0.0.1", port) then return c end
  c:close()
end

local function start_server()
  os.remove(port_file)
  local script = (here .. "/juliatex_server.jl"):gsub("\\", "/")
  if os.type == "windows" then
    -- Start-Process without redirections: the server does not inherit lualatex's output
    -- (if it did, latexmk/VimTeX would wait for the server to exit).
    -- It starts in TEMP: Windows would not let you delete or rename the document folder
    os.execute(string.format(
      'powershell -NoProfile -NonInteractive -Command "Start-Process -WindowStyle Hidden'
        .. " -WorkingDirectory '%s' -FilePath julia"
        .. " -ArgumentList '--startup-file=no','--project=%s','%s','%s'\"",
      temp, project, script, port_file))
  else
    os.execute(string.format('julia --startup-file=no --project="%s" "%s" "%s" >/dev/null 2>&1 &',
      project, script, port_file))
  end
end

function J.server(folder)
  local ok, socket = pcall(require, "socket")
  if not ok then return nil end
  local c = connect(socket)
  if not c then
    texio.write_nl("term and log", "juliatex: starting the Julia server...")
    start_server()
    for _ = 1, 200 do -- up to 20 s
      socket.sleep(0.1)
      c = connect(socket)
      if c then break end
    end
    if not c then return nil end
  end
  c:settimeout(nil) -- running may take as long as the code takes
  c:send(folder .. "\n")
  local resp = c:receive("*l")
  c:close()
  return resp and tonumber(resp:match("^ok (%d+)"))
end

-- Option [md]: <document>.md next to the PDF (pandoc + juliatex-md.lua), with the same
-- Julia outputs. Only when no other pass is needed, and only if something changed
-- (the .tex, an output or a figure); pandoc takes a few tenths of a second.
J.md = false
local function markdown()
  if not J.md then return end
  local parts = { read(tex.jobname .. ".tex") or "" }
  for n = 1, #blocks do parts[#parts + 1] = read(path(n, "out")) or "" end
  for _, f in ipairs(figures) do parts[#parts + 1] = read(f[1]) or "" end
  local hash = md5.sumhexa(table.concat(parts, "\1"))
  local output = tex.jobname .. ".md"
  if read(dir .. "/hash-md") == hash and lfs.isfile(output) then return end
  local pandoc = os.getenv("JULIATEX_PANDOC") or "pandoc"
  local cmd = string.format('%s -f latex+raw_tex -t gfm --wrap=none --lua-filter="%s"'
      .. ' -M juliatex-dir="%s" -o "%s" "%s"',
    pandoc, here .. "/juliatex-md.lua", dir, output, tex.jobname .. ".tex")
  if run(cmd) then
    write(dir .. "/hash-md", hash)
    texio.write_nl("term and log", "juliatex: " .. output .. " updated")
  else
    warning("could not write " .. output .. " (is pandoc installed and on the PATH?)")
  end
end

-- At the end of the document: if the code changed, run Julia and ask for another pass
function J.run()
  if #blocks == 0 then return markdown() end
  local parts = { project }
  for n, b in ipairs(blocks) do
    parts[#parts + 1] = n .. "\0" .. b.kind .. "\0" .. b.code
  end
  local hash = md5.sumhexa(table.concat(parts, "\1"))
  if read(dir .. "/hash") == hash then return markdown() end

  local kinds = {}
  for n, b in ipairs(blocks) do
    write(path(n, "jl"), b.code .. "\n")
    kinds[n] = b.kind
  end
  write(dir .. "/kinds", table.concat(kinds, "\n") .. "\n")

  local hashes = {}
  for n, b in ipairs(blocks) do hashes[n] = md5.sumhexa(b.kind .. "\0" .. b.code) end
  write(dir .. "/hashes", table.concat(hashes, "\n") .. "\n")

  local before = {}
  for n = 1, #blocks do before[n] = read(path(n, "out")) end

  -- Server first (live session: packages loaded, only from the block that changed);
  -- if it is not available, a fresh Julia runs everything in order
  local from = J.server(lfs.currentdir():gsub("\\", "/") .. "/" .. dir)
  if from then
    texio.write_nl("term and log", "juliatex: server ran from block " .. from
      .. " of " .. #blocks)
  else
    texio.write_nl("term and log", "juliatex: running " .. #blocks .. " blocks in Julia...")
    local cmd = string.format('julia --startup-file=no --project="%s" "%s" "%s"',
      project, runner, dir)
    if not run(cmd) then
      warning("Julia exited with an error; see " .. dir .. "/julia.log")
      return
    end
  end
  write(dir .. "/hash", hash)

  for n = 1, #blocks do
    if read(path(n, "out")) ~= before[n] then
      another_pass()
      return
    end
  end
  -- Figures that are new or differ from the copy included in this pass
  for _, f in ipairs(figures) do
    local current = read(f[1])
    if current and (not f[2] or read(f[2]) ~= current) then
      another_pass()
      return
    end
  end
  markdown()
end

return J
