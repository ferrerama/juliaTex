-- Neovim mínimo para LaTeX + Julia (juliatex), en Windows y Linux.
--   nvim -u nvim/init.lua analisis.tex
-- No toca tu configuración: los plugins y su lockfile quedan en nvim/.lazy/.
-- F5 en un .tex: compila continuo (latexmk) y abre el PDF; en un .jl: REPL con el archivo.
local o = vim.opt
o.autoindent = true
o.smartindent = true
o.expandtab = true
o.tabstop = 3
o.shiftwidth = 3
o.cursorline = true
o.number = true
-- Líneas largas: se ven partidas entre palabras y con sangría (no cambia el archivo)
o.linebreak = true
o.breakindent = true
o.showbreak = "↪ "
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local windows = vim.fn.has("win32") == 1
local aqui = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

-- Texto (.tex/.md): una oración por línea, sin corte automático (partiría también el
-- código de juliacode). Código Julia: guía en la columna 93 (guía de estilo: 92).
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
      vim.opt_local.spelllang = { "es", "en" }
    end
  end,
})

-- Visor de PDF: SumatraPDF en Windows (variable SUMATRA, PATH o instalación por defecto),
-- zathura en Linux si está; si no, el visor del sistema
local function sumatra()
  for _, ruta in ipairs({ os.getenv("SUMATRA") or "", vim.fn.exepath("SumatraPDF"),
    (os.getenv("LOCALAPPDATA") or "") .. "/SumatraPDF/SumatraPDF.exe" }) do
    if ruta ~= "" and vim.fn.executable(ruta) == 1 then return ruta end
  end
end

-- lazy.nvim (gestor de plugins), instalado junto a este archivo
local lazypath = aqui .. "/.lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
o.runtimepath:prepend(lazypath)

require("lazy").setup({
  {
    "lervag/vimtex",
    lazy = false, -- vimtex no debe cargarse de forma diferida
    init = function()
      vim.g.tex_flavor = "latex"
      vim.g.vimtex_compiler_method = "latexmk" -- lee el .latexmkrc del proyecto
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
      -- juliatex: código de Julia resaltado dentro de juliacode/juliarun
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
  root = aqui .. "/.lazy",
  lockfile = aqui .. "/lazy-lock.json",
  state = aqui .. "/.lazy/state.json",
  pkg = { cache = aqui .. "/.lazy/pkg-cache.lua" },
  readme = { root = aqui .. "/.lazy/readme" },
  rocks = { enabled = false },
})

-- F5: una sola tecla por tipo de archivo
local function f5()
  local ft = vim.bo.filetype
  vim.cmd("write")
  if ft == "tex" then
    vim.cmd("VimtexCompile") -- continuo: cada vez que guardas, PDF (y .md) al día
  elseif ft == "julia" then
    local archivo = vim.fn.expand("%:p"):gsub("\\", "/")
    vim.cmd("botright split | resize 12")
    vim.fn.jobstart({ "julia", "--project=@.", "-i", "-e", 'include("' .. archivo .. '")' },
      { term = true })
    vim.cmd("startinsert")
  else
    vim.notify("F5: sin comando para " .. ft, vim.log.levels.WARN)
  end
end
vim.keymap.set("n", "<F5>", f5, { desc = "Compilar / ejecutar" })
vim.keymap.set("v", "<C-c>", '"+y', { desc = "Copiar" })
