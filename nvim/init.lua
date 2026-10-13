-- Minimal Neovim for LaTeX + Julia (juliatex), on Windows and Linux.
--   cd example && nvim -u ../nvim/init.lua analysis.tex
-- It does not touch your own config: plugins and their lockfile live in nvim/.lazy/.
-- F5 in a .tex: continuous build (latexmk) and opens the PDF; in a .jl: REPL with the file.
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

-- Does the .tex load juliatex?
local function uses_juliatex(buf)
  local header = table.concat(vim.api.nvim_buf_get_lines(buf, 0, 200, false), "\n")
  return header:match("\\usepackage%s*%b[]%s*{juliatex}") ~= nil
    or header:match("\\usepackage%s*{juliatex}") ~= nil
end

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
      vim.env.JULIATEX_PROJECT = (not own) and vim.fs.dirname(pkgdir) .. "/example" or nil
    end
    vim.cmd("VimtexCompile") -- continuous: every save brings the PDF (and .md) up to date
  elseif ft == "julia" then
    local file = vim.fn.expand("%:p"):gsub("\\", "/")
    vim.cmd("botright split | resize 12")
    vim.fn.jobstart({ "julia", "--project=@.", "-i", "-e", 'include("' .. file .. '")' },
      { term = true })
    vim.cmd("startinsert")
  else
    vim.notify("F5: no command for " .. ft, vim.log.levels.WARN)
  end
end
vim.keymap.set("n", "<F5>", f5, { desc = "Build / run" })
vim.keymap.set("v", "<C-c>", '"+y', { desc = "Copy" })
