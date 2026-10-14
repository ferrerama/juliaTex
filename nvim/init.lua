-- Minimal Neovim for LaTeX + Julia (juliatex), on Windows and Linux.
--   cd example && nvim -u ../nvim/init.lua analysis.tex
-- It does not touch your own config: plugins and their lockfile live in nvim/.lazy/.
-- F5 in a .tex: continuous build (latexmk) and opens the PDF; in a .jl: REPL with the file.
-- Julia language server in .jl files and in the Julia code of a .tex (juliatex-lsp.lua).
local o = vim.opt
o.autoindent = true
o.smartindent = true
o.expandtab = true
o.tabstop = 3
o.shiftwidth = 3
o.cursorline = true
o.number = true
-- Long lines: shown wrapped between words and indented (the file is not changed)
o.linebreak = true
o.breakindent = true
o.showbreak = "↪ "
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local windows = vim.fn.has("win32") == 1
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

-- juliatex from this repository: any .tex finds the package and chktex its settings,
-- with no .latexmkrc or chktexrc in the document's folder
local pkgdir = vim.fn.fnamemodify(here .. "/../juliatex", ":p:h"):gsub("\\", "/")
vim.env.TEXINPUTS = pkgdir .. "//" .. (windows and ";" or ":") .. (vim.env.TEXINPUTS or "")
vim.env.CHKTEXRC = pkgdir

-- Prose (.tex/.md): one sentence per line, no automatic wrapping (it would also break
-- the code in juliacode). Julia code: guide at column 93 (style guide: 92).
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "markdown", "julia" },
  callback = function(ev)
    vim.opt_local.formatoptions:remove("t")
    if ev.match == "julia" then
      vim.opt_local.textwidth = 92
      vim.opt_local.colorcolumn = "+1"
    else
      vim.opt_local.textwidth = 0
      vim.opt_local.spell = true
      vim.opt_local.spelllang = { "en" }
    end
  end,
})

-- PDF viewer: SumatraPDF on Windows (SUMATRA variable, PATH or default install),
-- zathura on Linux if present; otherwise the system viewer
local function sumatra()
  for _, path in ipairs({ os.getenv("SUMATRA") or "", vim.fn.exepath("SumatraPDF"),
    (os.getenv("LOCALAPPDATA") or "") .. "/SumatraPDF/SumatraPDF.exe" }) do
    if path ~= "" and vim.fn.executable(path) == 1 then return path end
  end
end

-- lazy.nvim (plugin manager), installed next to this file
local lazypath = here .. "/.lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
o.runtimepath:prepend(lazypath)

require("lazy").setup({
  {
    "lervag/vimtex",
    lazy = false, -- vimtex must not be lazy-loaded
    init = function()
      vim.g.tex_flavor = "latex"
      vim.g.vimtex_compiler_method = "latexmk" -- reads the project's .latexmkrc
      vim.g.vimtex_quickfix_open_on_warning = 0
      local sumatra = windows and sumatra()
      if sumatra then
        vim.g.vimtex_view_method = "general"
        vim.g.vimtex_view_general_viewer = sumatra
        vim.g.vimtex_view_general_options = "-reuse-instance -forward-search @tex @line @pdf"
      elseif vim.fn.executable("zathura") == 1 then
        vim.g.vimtex_view_method = "zathura"
      else
        vim.g.vimtex_view_method = "general"
      end
      -- juliatex: Julia code highlighted inside juliacode/juliarun
      vim.g.vimtex_syntax_custom_envs = {
        { name = "juliacode", region = "texJuliaZone", nested = "julia" },
        { name = "juliarun", region = "texJuliaZone", nested = "julia" },
      }
    end,
  },
  -- Prose like a page: the .tex/.md window as wide as an APA 7 line (Times 12 pt, 2.54 cm
  -- margins: ~95 characters), on the left and frameless: only padding on the right,
  -- no "~" and no divider; see the "page" autocmd below
  {
    "shortcuts/no-neck-pain.nvim",
    lazy = false,
    opts = {
      width = 95,
      buffers = {
        left = { enabled = false },
        right = { wo = { fillchars = "eob: " } },
      },
    },
  },
  {
    "shaunsingh/nord.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.nord_disable_background = true
      vim.cmd.colorscheme("nord")
    end,
  },
}, {
  root = here .. "/.lazy",
  lockfile = here .. "/lazy-lock.json",
  state = here .. "/.lazy/state.json",
  pkg = { cache = here .. "/.lazy/pkg-cache.lua" },
  readme = { root = here .. "/.lazy/readme" },
  rocks = { enabled = false },
})

-- "Page" (no-neck-pain): 95 columns on the left only while editing prose; code goes back
-- to the full width. Terminals and quickfix (buftype ~= "") do not count.
-- The divider is drawn by the left window: hidden with "vert: " while the page lasts and
-- restored to the global value when it goes away.
-- The plugin gives each side half of the free space (it is meant for centering); with no
-- left side, the right one must take everything between the page and itself.
do
  local ui = require("no-neck-pain.ui")
  local state = require("no-neck-pain.state")
  local side_width = ui.get_side_width
  ui.get_side_width = function(side)
    local w = side_width(side)
    if side ~= "right" or w <= 0 then return w end
    local curr, right = state:get_side_id("curr"), state:get_side_id("right")
    if curr and right and vim.api.nvim_win_is_valid(curr) and vim.api.nvim_win_is_valid(right) then
      return math.max(vim.api.nvim_win_get_width(curr) + vim.api.nvim_win_get_width(right)
        - _G.NoNeckPain.config.width, 1)
    end
    return 2 * w
  end
end
local prose = { tex = true, plaintex = true, markdown = true }
local function page_on()
  return _G.NoNeckPain and _G.NoNeckPain.state and _G.NoNeckPain.state.enabled
end
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= "" or vim.bo[ev.buf].filetype == "" then return end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(ev.buf) or vim.api.nvim_get_current_buf() ~= ev.buf then return end
      local wants = prose[vim.bo[ev.buf].filetype] == true
      if wants and not page_on() then
        require("no-neck-pain").enable()
        vim.opt_local.fillchars:append({ vert = " " })
      elseif page_on() and not wants then
        require("no-neck-pain").disable()
        vim.cmd("setlocal fillchars<")
      end
    end)
  end,
})

-- Terminal: with the page on it opens below it, just as wide, and the right side keeps
-- going from top to bottom, with no divider; otherwise across the full width.
local function open_terminal(cmd)
  local on_page = page_on() and vim.bo.filetype ~= "no-neck-pain"
  -- "new", not "split": jobstart turns the current buffer into the terminal
  vim.cmd(on_page and "belowright new" or "botright new")
  vim.cmd("resize 12")
  vim.fn.jobstart(cmd, { term = true })
  if on_page then vim.opt_local.fillchars:append({ vert = " " }) end
  vim.cmd("startinsert")
end
vim.keymap.set("n", "<leader>ft", function()
  open_terminal(windows and { "pwsh", "-NoLogo" } or { vim.o.shell })
end, { desc = "Terminal" })

-- Julia language server in .jl files and inside juliacode/juliarun/\juliav of a .tex.
-- Code with no Project.toml above it uses the example's environment, as F5 does.
local example_env = vim.fs.dirname(pkgdir) .. "/example"
local lsp = dofile(here .. "/juliatex-lsp.lua")
lsp.setup({ server_env = here:gsub("\\", "/") .. "/lsp", default_env = example_env })
local uses_juliatex = lsp.uses_juliatex

-- F5: a single key per file type
local function f5()
  local ft = vim.bo.filetype
  vim.cmd("write")
  if ft == "tex" then
    -- juliatex needs LuaLaTeX with -shell-escape (to launch Julia): no .latexmkrc required
    if uses_juliatex(0) and vim.b.vimtex then
      vim.cmd([[let b:vimtex.compiler.get_engine = {-> '-lualatex -shell-escape'}]])
      -- No Project.toml next to the .tex or above it: the example's environment (has Plots)
      local own = vim.fs.find("Project.toml", { upward = true, path = vim.fn.expand("%:p:h") })[1]
      vim.env.JULIATEX_PROJECT = (not own) and example_env or nil
    end
    vim.cmd("VimtexCompile") -- continuous: every save brings the PDF (and .md) up to date
  elseif ft == "julia" then
    local file = vim.fn.expand("%:p"):gsub("\\", "/")
    open_terminal({ "julia", "--project=@.", "-i", "-e", 'include("' .. file .. '")' })
  else
    vim.notify("F5: no command for " .. ft, vim.log.levels.WARN)
  end
end
vim.keymap.set("n", "<F5>", f5, { desc = "Build / run" })
vim.keymap.set("v", "<C-c>", '"+y', { desc = "Copy" })
