-- The Julia language server (LanguageServer.jl) in .jl files and inside the .tex files
-- that load juliatex: juliacode, juliarun and \juliav{...}.
-- A .tex gets a mirror <doc>.juliatex.jl next to it: its Julia code on the SAME line and
-- column, everything else blank. julials analyses the mirror; its diagnostics are copied
-- to the .tex, and a minimal in-memory server (juliatex-ls) forwards completion, hover,
-- signature help and go-to-definition to it. The mirror is deleted when the .tex or
-- Neovim closes.
local M = {}
local api = vim.api

local ns = api.nvim_create_namespace("juliatex")
local docs = {} -- [.tex buf] = { mirror, path, uri, tex_uri, lines, julia = {[row0]=kind} }

-- The Julia parts of each line of the .tex. Returns the mirror's lines and which rows
-- (0-based) have code: "block" (copied as is) or "value" (\juliav, columns remapped)
local function extract(lines)
  local mirror, julia, env = {}, {}, nil
  for i, l in ipairs(lines) do
    local row = ""
    if env then
      if l:match("^%s*\\end%s*{" .. env .. "}") then
        env = nil
      else
        row = l
        julia[i - 1] = "block"
      end
    elseif not l:match("^%s*%%") then
      env = l:match("^%s*\\begin%s*{(julia%a+)}")
      if env ~= "juliacode" and env ~= "juliarun" then env = nil end
      -- \juliav{expr}: the expression at its column (in UTF-16 units, like LSP positions;
      -- padded with spaces) and ';' between several on the same line
      for start, arg in l:gmatch("()\\juliav(%b{})") do
        local col = vim.str_utfindex(l:sub(1, start - 1 + #"\\juliav{"), "utf-16")
        local len = vim.str_utfindex(row, "utf-16")
        if len > 0 then
          row = row .. string.rep(" ", col - len - 1) .. ";"
          len = col
        end
        row = row .. string.rep(" ", col - len) .. arg:sub(2, -2)
        julia[i - 1] = "value"
      end
    end
    mirror[i] = row
  end
  return mirror, julia
end

local function write_file(path, lines)
  local f = io.open(path, "wb")
  if f then
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
  end
end

local function sync(buf)
  local d = docs[buf]
  if not d or not api.nvim_buf_is_valid(d.mirror) then return end
  local mirror, julia = extract(api.nvim_buf_get_lines(buf, 0, -1, false))
  d.julia = julia
  if vim.deep_equal(mirror, d.lines) then return end
  d.lines = mirror
  api.nvim_buf_set_lines(d.mirror, 0, -1, false, mirror)
  vim.bo[d.mirror].modified = false
end

local function julials(d)
  return vim.lsp.get_clients({ bufnr = d.mirror, name = "julials" })[1]
end

-- Replaces the mirror's URI with the .tex's anywhere in a result
local function to_tex(x, d)
  if type(x) == "string" then return x == d.uri and d.tex_uri or x end
  if type(x) ~= "table" then return x end
  for k, v in pairs(x) do x[k] = to_tex(v, d) end
  return x
end

-- In-memory server attached to the .tex: answers only with the cursor on Julia code
local function server(buf)
  return function()
    local closing, id = false, 0
    local srv = {}
    function srv.request(method, params, callback)
      id = id + 1
      if method == "initialize" then
        callback(nil, {
          capabilities = {
            hoverProvider = true,
            definitionProvider = true,
            signatureHelpProvider = { triggerCharacters = { "(", "," } },
            completionProvider = { triggerCharacters = { "." } },
          },
          serverInfo = { name = "juliatex-ls" },
        })
        return true, id
      end
      local d = docs[buf]
      local pos = params and params.position
      if d then sync(buf) end
      local c = d and julials(d)
      if not (c and pos and d.julia[pos.line]) then
        vim.schedule(function() callback(nil, nil) end)
        return true, id
      end
      local p = vim.deepcopy(params)
      p.textDocument = { uri = d.uri }
      c:request(method, p, function(err, result)
        callback(err, to_tex(result, d))
      end, d.mirror)
      return true, id
    end
    function srv.notify() return true end
    function srv.is_closing() return closing end
    function srv.terminate() closing = true end
    return srv
  end
end

local function clean(buf)
  local d = docs[buf]
  if not d then return end
  docs[buf] = nil
  if api.nvim_buf_is_valid(d.mirror) then api.nvim_buf_delete(d.mirror, { force = true }) end
  os.remove(d.path)
end

local function attach(buf)
  if docs[buf] then return end
  local tex = api.nvim_buf_get_name(buf)
  local path = vim.fn.fnamemodify(tex, ":r") .. ".juliatex.jl"
  local lines, julia = extract(api.nvim_buf_get_lines(buf, 0, -1, false))
  -- On disk before julials starts: LanguageServer.jl only publishes diagnostics for
  -- files it finds in its root folder
  write_file(path, lines)
  local mirror = vim.fn.bufadd(path)
  vim.fn.bufload(mirror)
  vim.bo[mirror].buflisted = false
  vim.bo[mirror].swapfile = false
  docs[buf] = {
    mirror = mirror, path = path, lines = lines, julia = julia,
    uri = vim.uri_from_bufnr(mirror), tex_uri = vim.uri_from_bufnr(buf),
  }

  local group = api.nvim_create_augroup("juliatex" .. buf, {})
  -- :wa also "saves" the mirror: write it ourselves and do not mark it as modified
  api.nvim_create_autocmd("BufWriteCmd", {
    group = group, buffer = mirror,
    callback = function()
      write_file(path, api.nvim_buf_get_lines(mirror, 0, -1, false))
      vim.bo[mirror].modified = false
    end,
  })
  api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = group, buffer = buf,
    callback = function() sync(buf) end,
  })
  -- Mirror diagnostics -> .tex (\juliav columns: from the mirror's to the .tex's bytes)
  api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(ev)
      local d = docs[buf]
      if not d or ev.buf ~= d.mirror then return end
      local tex_lines = api.nvim_buf_get_lines(buf, 0, -1, false)
      local diags = {}
      for _, x in ipairs(vim.diagnostic.get(d.mirror)) do
        local y = vim.deepcopy(x)
        y.bufnr, y.namespace = buf, ns
        local l = tex_lines[y.lnum + 1]
        if d.julia[y.lnum] == "value" and l then
          local ok1, c1 = pcall(vim.str_byteindex, l, "utf-16", y.col, false)
          local ok2, c2 = pcall(vim.str_byteindex, l, "utf-16", y.end_col or y.col, false)
          y.col, y.end_col = ok1 and c1 or y.col, ok2 and c2 or y.end_col
        end
        table.insert(diags, y)
      end
      vim.diagnostic.set(ns, buf, diags)
    end,
  })
  api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group, buffer = buf,
    callback = function() clean(buf) end,
  })
  api.nvim_create_autocmd("ExitPre", {
    group = group,
    callback = function() clean(buf) end,
  })

  -- julials attaches to the mirror through its filetype
  vim.bo[mirror].filetype = "julia"
  vim.lsp.start({ name = "juliatex-ls", cmd = server(buf) }, { bufnr = buf, reuse_client = function() return false end })
end

-- Does the .tex load juliatex?
function M.uses_juliatex(buf)
  local header = table.concat(api.nvim_buf_get_lines(buf, 0, 200, false), "\n")
  return header:match("\\usepackage%s*%b[]%s*{juliatex}") ~= nil
    or header:match("\\usepackage%s*{juliatex}") ~= nil
end

-- opts.server_env: folder with the server (Project.toml with LanguageServer, server.jl)
-- opts.default_env: Julia environment for code with no Project.toml above it
function M.setup(opts)
  local manifest = opts.server_env .. "/Manifest.toml"
  vim.lsp.config("julials", {
    cmd = { "julia", "--startup-file=no", "--history-file=no", "--project=" .. opts.server_env,
      opts.server_env .. "/server.jl", opts.default_env },
    filetypes = { "julia" },
    -- Root: the folder of the Project.toml above the file (as F5 does), or else the file's
    -- folder; never the .git, which would index the whole repository
    root_dir = function(bufnr, on_dir)
      on_dir(vim.fs.root(bufnr, "Project.toml") or vim.fs.dirname(api.nvim_buf_get_name(bufnr)))
    end,
    before_init = function()
      if not vim.uv.fs_stat(manifest) then
        vim.notify("juliatex: installing LanguageServer.jl in nvim/lsp/ (first time only, a few minutes)")
      end
    end,
    on_init = function(client)
      -- nvim 0.12 sends didSave to every client with the same sync kind, not only to the
      -- saved buffer's: saving the .tex reached julials, which does not know it, and
      -- LanguageServer.jl crashed with a KeyError. Only let its own through.
      local notify = client.notify
      client.notify = function(self, method, params, bufnr)
        if method == "textDocument/didSave" and bufnr and not self.attached_buffers[bufnr] then
          return true
        end
        return notify(self, method, params, bufnr)
      end
      -- Packages resolved with the root's Project.toml, or else with the default
      -- environment; never Julia's global one
      -- (LanguageServer 6 renamed the notification; the Manifest says which one is running)
      local own = client.root_dir and vim.uv.fs_stat(client.root_dir .. "/Project.toml")
      local f = io.open(manifest)
      local major = f and f:read("*a"):match('%[%[deps%.LanguageServer%]%].-\nversion = "(%d+)')
      if f then f:close() end
      client:notify(major == "4" and "julia/activateenvironment" or "julia/setEnvironmentPath",
        { envPath = own and client.root_dir or opts.default_env })
    end,
  })
  vim.lsp.enable("julials")

  -- Native completion: pops up after "."; Ctrl-Space asks for it anywhere
  vim.o.completeopt = "menu,menuone,noselect,popup"
  api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if client and client:supports_method("textDocument/completion") then
        vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
        vim.keymap.set("i", "<C-Space>", vim.lsp.completion.get, { buffer = ev.buf, desc = "Complete" })
      end
    end,
  })
  vim.diagnostic.config({ virtual_text = true })

  api.nvim_create_autocmd("FileType", {
    pattern = "tex",
    callback = function(ev)
      if M.uses_juliatex(ev.buf) then attach(ev.buf) end
    end,
  })
end

return M
